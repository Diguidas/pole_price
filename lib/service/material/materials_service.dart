// lib/service/materials_service.dart

import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:pole_price/models/material/material_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MaterialsService {
  final SupabaseClient supabase;

  MaterialsService(this.supabase);

  // ── Listar materiais ────────────────────────────────────────────────────────

  /// Busca todos os materiais da tabela materials (view materials_full se existir).
  /// CPV/Ded%/DV% vêm de `product_costs` (import por planilha, período mais
  /// recente) — as colunas equivalentes em `materials` são do fluxo legado
  /// (CSV) e não são mais a fonte de verdade.
  Future<List<MaterialSap>> listar({
    String? busca,
    String? empresa,
    String? marca,
  }) async {
    var query = supabase.from('materials').select().order('description');

    final res = await query;
    final rows = (res as List).cast<Map<String, dynamic>>();

    final codigos = rows
        .map((r) => r['material_code']?.toString())
        .whereType<String>()
        .toSet()
        .toList();

    final custosRes = codigos.isEmpty
        ? <dynamic>[]
        : await supabase
            .from('product_costs')
            .select('product_code, cost_value, ded_pct, dv_pct, period')
            .inFilter('product_code', codigos);

    // 'period' é texto e pode conter formatos legados fora do padrão
    // AAAAMM — só considera períodos de 6 dígitos ao escolher o mais recente.
    final periodoRegex = RegExp(r'^\d{6}$');
    final melhorPeriodoPorCodigo = <String, String>{};
    for (final c in custosRes) {
      final code = c['product_code']?.toString();
      final periodo = c['period']?.toString();
      if (code == null || periodo == null || !periodoRegex.hasMatch(periodo)) {
        continue;
      }
      final atual = melhorPeriodoPorCodigo[code];
      if (atual == null || periodo.compareTo(atual) > 0) {
        melhorPeriodoPorCodigo[code] = periodo;
      }
    }

    final cpvMap = <String, dynamic>{};
    final dedMap = <String, dynamic>{};
    final dvMap = <String, dynamic>{};
    for (final c in custosRes) {
      final code = c['product_code']?.toString();
      final periodo = c['period']?.toString();
      if (code == null || periodo != melhorPeriodoPorCodigo[code]) continue;
      cpvMap[code] = c['cost_value'];
      dedMap[code] = c['ded_pct'];
      dvMap[code] = c['dv_pct'];
    }

    final lista = rows.map((j) {
      final code = j['material_code']?.toString();
      final merged = Map<String, dynamic>.from(j)
        ..['cpv_reais'] = cpvMap[code]
        ..['deducoes_pct'] = dedMap[code]
        ..['despesas_var_pct'] = dvMap[code]
        // cpv_pct/deducoes_reais/despesas_var_reais eram só do fluxo legado
        ..['cpv_pct'] = null
        ..['deducoes_reais'] = null
        ..['despesas_var_reais'] = null;
      return MaterialSap.fromJson(merged);
    }).toList();

    if (busca != null && busca.isNotEmpty) {
      final q = busca.toLowerCase();
      return lista
          .where(
            (m) =>
                m.materialCode.toLowerCase().contains(q) ||
                m.description.toLowerCase().contains(q) ||
                (m.marca?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }

    return lista;
  }

  // ── Vínculo de preço (pai/filho dentro do agrupamento) ─────────────────────

  /// Define (ou remove, passando null em ambos) o vínculo de preço de um
  /// material filho em relação a um material pai do mesmo agrupamento.
  Future<void> salvarVinculoPreco({
    required String materialCode,
    String? paiCode,
    double? excecaoPct,
  }) async {
    await supabase
        .from('materials')
        .update({
          'material_pai_code': paiCode,
          'excecao_preco_pct': excecaoPct,
        })
        .eq('material_code', materialCode);
  }

  // ── Sincronizar SAP ─────────────────────────────────────────────────────────

  /// Chama a Edge Function sync-materials.
  /// Retorna { total_from_sap, upserted, errors, duration_ms }
  Future<SyncResult> syncSap() async {
    final res = await supabase.functions.invoke('get_materiais');

    if (res.status != 200) {
      throw Exception(
        'Falha na sincronização SAP (${res.status}): ${res.data}',
      );
    }

    final data = res.data as Map<String, dynamic>;
    return SyncResult(
      totalFromSap: (data['total_from_sap'] as num?)?.toInt() ?? 0,
      upserted: (data['upserted'] as num?)?.toInt() ?? 0,
      errors: (data['errors'] as List?)?.length ?? 0, // ← aqui estava quebrando
      durationMs: (data['duration_ms'] as num?)?.toInt() ?? 0,
    );
  }

  // ── Download planilha modelo (agrupamento + vínculo) ────────────────────────

  /// Gera a planilha .xlsx para preenchimento da hierarquia e do vínculo de
  /// preço pai/filho. Retorna os bytes do arquivo.
  Future<Uint8List> gerarPlanilhaModelo(List<MaterialSap> materiais) async {
    final header = [
      'material_code',
      'description',
      // Campos SAP — somente leitura (referência)
      'unidade_venda',
      'peso_unidade',
      'peso_caixa',
      'fator_conversao',
      // Agrupadores — editáveis
      'empresa',
      'marca',
      'gramatura',
      'categoria',
      'linha',
      'agrupamento_preco',
      // Vínculo de preço pai/filho — editáveis. excecao_preco_pct em número
      // percentual (ex: 20 = +20%, -5 = -5%), igual ao diálogo de vínculo da
      // tela de Materiais — não é a fração salva no banco (0,20).
      'material_pai_code',
      'excecao_preco_pct',
    ];

    final excel = Excel.createExcel();
    final nomeAba = excel.getDefaultSheet()!;
    final sheet = excel[nomeAba];

    sheet.appendRow(header.map((h) => TextCellValue(h)).toList());

    for (final m in materiais) {
      sheet.appendRow([
        TextCellValue(m.materialCode),
        TextCellValue(m.description),
        TextCellValue(m.unidadeVenda ?? ''),
        TextCellValue(m.pesoUnidade?.toString() ?? ''),
        TextCellValue(m.pesoCaixa?.toString() ?? ''),
        TextCellValue(m.fatorConversao?.toStringAsFixed(4) ?? ''),
        TextCellValue(m.empresa ?? ''),
        TextCellValue(m.marca ?? ''),
        TextCellValue(m.gramatura ?? ''),
        TextCellValue(m.categoria ?? ''),
        TextCellValue(m.linha ?? ''),
        TextCellValue(m.agrupamentoPreco ?? ''),
        TextCellValue(m.materialPaiCode ?? ''),
        TextCellValue(
          m.excecaoPrecoPct != null
              ? (m.excecaoPrecoPct! * 100).toStringAsFixed(2)
              : '',
        ),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Falha ao gerar a planilha.');
    return Uint8List.fromList(bytes);
  }

  // ── Download planilha de custos (CPV / Dedução / Despesa) ───────────────────

  /// Gera a planilha .xlsx de custos pré-preenchida com o CPV/Dedução%/
  /// Despesa Var% mais recentes de cada material (quando existirem), no
  /// mesmo formato aceito por [processarUploadCustos] (Periodo/Cod/Material/
  /// Valor/Dedução/Despesa).
  Future<Uint8List> gerarPlanilhaCustos(List<MaterialSap> materiais) async {
    final codigos = materiais.map((m) => m.materialCode).toList();

    final custosRes = codigos.isEmpty
        ? <dynamic>[]
        : await supabase
            .from('product_costs')
            .select('product_code, cost_value, ded_pct, dv_pct, period')
            .inFilter('product_code', codigos);

    // Mesma lógica de "período mais recente" usada em listar().
    final periodoRegex = RegExp(r'^\d{6}$');
    final melhorPeriodoPorCodigo = <String, String>{};
    for (final c in custosRes) {
      final code = c['product_code']?.toString();
      final periodo = c['period']?.toString();
      if (code == null || periodo == null || !periodoRegex.hasMatch(periodo)) {
        continue;
      }
      final atual = melhorPeriodoPorCodigo[code];
      if (atual == null || periodo.compareTo(atual) > 0) {
        melhorPeriodoPorCodigo[code] = periodo;
      }
    }

    final Map<String, Map<String, dynamic>> custoPorCodigo = {};
    for (final c in custosRes) {
      final code = c['product_code']?.toString();
      final periodo = c['period']?.toString();
      if (code == null || periodo != melhorPeriodoPorCodigo[code]) continue;
      custoPorCodigo[code] = c;
    }

    final excel = Excel.createExcel();
    final nomeAba = excel.getDefaultSheet()!;
    final sheet = excel[nomeAba];

    sheet.appendRow(
      ['Periodo', 'Cod', 'Material', 'Valor', 'Dedução', 'Despesa']
          .map((h) => TextCellValue(h))
          .toList(),
    );

    // Dedução%/Despesa% ficam em número percentual (5 = 5%) — mesmo formato
    // que o financeiro já usa; a fração (0,05) é só o que fica salvo no banco.
    String pctOuVazio(dynamic v) {
      final d = v != null ? double.tryParse(v.toString()) : null;
      return d != null ? (d * 100).toStringAsFixed(2) : '';
    }

    for (final m in materiais) {
      final c = custoPorCodigo[m.materialCode];
      sheet.appendRow([
        TextCellValue(c?['period']?.toString() ?? ''),
        TextCellValue(m.materialCode),
        TextCellValue(m.description),
        TextCellValue(c?['cost_value']?.toString() ?? ''),
        TextCellValue(pctOuVazio(c?['ded_pct'])),
        TextCellValue(pctOuVazio(c?['dv_pct'])),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Falha ao gerar a planilha de custos.');
    return Uint8List.fromList(bytes);
  }

  // ── Upload e parse da planilha ──────────────────────────────────────────────

  /// Lê o .xlsx enviado pelo usuário e faz upsert em materials.
  /// Retorna { atualizados, erros, mensagensErro }
  Future<UploadResult> processarUpload(Uint8List bytes) async {
    final linhas = _readXlsxRows(bytes)
        .where((l) => l.any((c) => c.trim().isNotEmpty))
        .toList();
    if (linhas.length < 2) {
      throw Exception('Planilha vazia ou sem dados além do cabeçalho.');
    }

    final header = linhas[0];
    final idx = _buildIndex(header);

    final erros = <String>[];
    final registros = <Map<String, dynamic>>[];

    for (var i = 1; i < linhas.length; i++) {
      final cols = linhas[i];
      final code = _col(cols, idx, 'material_code');
      if (code.isEmpty) {
        erros.add('Linha ${i + 1}: material_code vazio — ignorado.');
        continue;
      }

      // Campos proibidos: description, unidade_venda, peso_*, fator_conversao
      // são ignorados mesmo se preenchidos (proteção contra sobrescrever SAP)
      final rec = <String, dynamic>{'material_code': code};

      void addStr(String col) {
        final v = _col(cols, idx, col);
        if (v.isNotEmpty) rec[col] = v;
      }

      addStr('empresa');
      addStr('marca');
      addStr('gramatura');
      addStr('categoria');
      addStr('linha');
      addStr('agrupamento_preco');

      // material_pai_code: string vazia explícita remove o vínculo; ausente
      // na planilha (coluna não preenchida em nenhuma linha) não mexe.
      final paiCol = _col(cols, idx, 'material_pai_code');
      if (idx.containsKey('material_pai_code')) {
        if (paiCol.isEmpty) {
          rec['material_pai_code'] = null;
        } else if (paiCol == code) {
          erros.add(
            'Linha ${i + 1}: material_pai_code não pode ser o próprio material ($code) — ignorado.',
          );
        } else {
          rec['material_pai_code'] = paiCol;
        }
      }

      // excecao_preco_pct vem em número percentual (20 = +20%) — converte
      // para a fração salva no banco (0,20).
      final excCol = _col(cols, idx, 'excecao_preco_pct');
      if (idx.containsKey('excecao_preco_pct')) {
        if (excCol.isEmpty) {
          rec['excecao_preco_pct'] = null;
        } else {
          final pct = double.tryParse(excCol.replaceAll(',', '.'));
          if (pct == null) {
            erros.add(
              'Linha ${i + 1}: excecao_preco_pct inválido ("$excCol") — ignorado.',
            );
          } else {
            rec['excecao_preco_pct'] = pct / 100;
          }
        }
      }

      registros.add(rec);
    }

    if (registros.isEmpty) {
      return UploadResult(
        atualizados: 0,
        erros: erros.length,
        mensagensErro: erros,
      );
    }

    // UPDATE individual por material_code (nunca cria registro novo)
    var atualizados = 0;
    for (final rec in registros) {
      final code = rec['material_code'] as String;
      final campos = Map<String, dynamic>.from(rec)..remove('material_code');
      if (campos.isEmpty) continue;
      try {
        await supabase
            .from('materials')
            .update(campos)
            .eq('material_code', code);
        atualizados++;
      } catch (e) {
        erros.add('Erro ao atualizar $code: $e');
      }
    }

    return UploadResult(
      atualizados: atualizados,
      erros: erros.length,
      mensagensErro: erros,
    );
  }

  // ── Import CPV / Dedução / Despesa (planilha xlsx) ─────────────────────────

  /// Lê a planilha de import (Periodo, Segmento, Cod, Material, Valor,
  /// dedução, Despesa) e faz upsert em `product_costs` por (product_code, period).
  /// Importa todas as linhas independente do segmento (Revenda/Industrializados) —
  /// cada material só aparece em um segmento na planilha, então não há conflito
  /// real; se por algum motivo a mesma chave (material, período) se repetir, a
  /// última ocorrência prevalece (ver deduplicação abaixo).
  Future<UploadResult> processarUploadCustos(Uint8List bytes) async {
    final rows = _readXlsxRows(bytes);
    if (rows.length < 2) {
      throw Exception('Planilha vazia ou sem dados além do cabeçalho.');
    }

    final header = rows.first.map((c) => c.trim().toLowerCase()).toList();

    int colIndex(List<String> aliases) {
      for (final alias in aliases) {
        final i = header.indexOf(alias);
        if (i != -1) return i;
      }
      return -1;
    }

    final idxPeriodo = colIndex(['periodo']);
    final idxCod = colIndex(['cod']);
    final idxValor = colIndex(['valor']);
    final idxDeducao = colIndex(['dedução', 'deducao']);
    final idxDespesa = colIndex(['despesa']);

    if (idxPeriodo == -1 || idxCod == -1 || idxValor == -1) {
      throw Exception(
        'Planilha fora do formato esperado (colunas Periodo/Cod/Valor não encontradas).',
      );
    }

    String cellStr(List<String> row, int i) =>
        i == -1 || i >= row.length ? '' : row[i].trim();

    double? cellNum(List<String> row, int i) {
      final v = cellStr(row, i);
      if (v.isEmpty) return null;
      return double.tryParse(v.replaceAll(',', '.'));
    }

    // Dedução/Despesa vêm em número percentual (5 = 5%) — converte para a
    // fração salva no banco (0,05), que é o que o motor de preço espera.
    double? cellPct(List<String> row, int i) {
      final v = cellNum(row, i);
      return v != null ? v / 100 : null;
    }

    final erros = <String>[];
    // Mapa por (product_code, period) — deduplica dentro do lote, já que o
    // Postgres rejeita upsert com a mesma chave duas vezes na mesma chamada.
    // Em caso de linha repetida, a última prevalece.
    final registrosPorChave = <String, Map<String, dynamic>>{};

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final linhaNum = i + 1;

      final cod = cellStr(row, idxCod);
      if (cod.isEmpty) {
        erros.add('Linha $linhaNum: código do material vazio — ignorado.');
        continue;
      }

      final periodo = cellStr(row, idxPeriodo);
      final cpv = cellNum(row, idxValor);
      if (periodo.isEmpty || cpv == null) {
        erros.add('Linha $linhaNum: período ou CPV inválido — ignorado.');
        continue;
      }

      final chave = '$cod|$periodo';
      if (registrosPorChave.containsKey(chave)) {
        erros.add(
          'Linha $linhaNum: material $cod já apareceu para o período $periodo — mantida a última ocorrência.',
        );
      }

      registrosPorChave[chave] = {
        'product_code': cod,
        'period': periodo,
        'cost_value': cpv,
        'ded_pct': cellPct(row, idxDeducao),
        'dv_pct': cellPct(row, idxDespesa),
      };
    }

    var registros = registrosPorChave.values.toList();

    if (registros.isEmpty) {
      return UploadResult(
        atualizados: 0,
        erros: erros.length,
        mensagensErro: erros,
      );
    }

    // product_costs.product_code é FK para products — materiais da planilha
    // que ainda não foram sincronizados do catálogo SAP seriam rejeitados
    // em bloco pelo upsert. Filtra fora e avisa, em vez de abortar tudo.
    final codigos = registros.map((r) => r['product_code'] as String).toSet().toList();
    final existentesRes = await supabase
        .from('products')
        .select('code')
        .inFilter('code', codigos);
    final existentes = (existentesRes as List)
        .map((r) => r['code']?.toString())
        .whereType<String>()
        .toSet();

    final faltantes = codigos.where((c) => !existentes.contains(c)).toSet();
    if (faltantes.isNotEmpty) {
      registros = registros
          .where((r) => existentes.contains(r['product_code']))
          .toList();
      erros.insert(
        0,
        '${faltantes.length} material(is) da planilha ainda não estão cadastrados '
        '(sincronize o catálogo SAP antes de importar): ${faltantes.take(20).join(', ')}'
        '${faltantes.length > 20 ? '...' : ''}',
      );
    }

    var atualizados = 0;
    if (registros.isNotEmpty) {
      try {
        await supabase
            .from('product_costs')
            .upsert(registros, onConflict: 'product_code,period');
        atualizados = registros.length;
      } catch (e) {
        erros.insert(0, 'Erro ao gravar custos: $e');
      }
    }

    return UploadResult(
      atualizados: atualizados,
      erros: erros.length,
      mensagensErro: erros,
    );
  }

  // ── Leitura de .xlsx (via pacote excel) ──────────────────────────────────

  /// Lê a primeira planilha de um arquivo .xlsx e retorna as linhas como
  /// texto puro, já convertendo os tipos de célula (texto/número/data) do
  /// pacote `excel` para string.
  List<List<String>> _readXlsxRows(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw Exception('Nenhuma planilha encontrada dentro do arquivo .xlsx.');
    }
    final sheet = excel.tables[excel.tables.keys.first]!;
    return sheet.rows
        .map((row) => row.map((cell) => cell?.value?.toString() ?? '').toList())
        .toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Map<String, int> _buildIndex(List<String> header) {
    return {
      for (var i = 0; i < header.length; i++) header[i].trim().toLowerCase(): i,
    };
  }

  String _col(List<String> cols, Map<String, int> idx, String name) {
    final i = idx[name];
    if (i == null || i >= cols.length) return '';
    return cols[i].trim();
  }
}

// ── Resultado do sync SAP ───────────────────────────────────────────────────

class SyncResult {
  final int totalFromSap;
  final int upserted;
  final int errors;
  final int durationMs;

  const SyncResult({
    required this.totalFromSap,
    required this.upserted,
    required this.errors,
    required this.durationMs,
  });
}

// ── Resultado do upload ─────────────────────────────────────────────────────

class UploadResult {
  final int atualizados;
  final int erros;
  final List<String> mensagensErro;

  const UploadResult({
    required this.atualizados,
    required this.erros,
    required this.mensagensErro,
  });
}