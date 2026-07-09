// lib/service/materials_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:pole_price/models/material/material_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart';

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

  // ── Download planilha modelo ────────────────────────────────────────────────

  /// Gera o CSV modelo para preenchimento da hierarquia e custos.
  /// Retorna os bytes do CSV.
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
      // Custos — editáveis
      'cpv_reais',
      'cpv_pct',
      'deducoes_pct',
      'deducoes_reais',
      'despesas_var_pct',
      'despesas_var_reais',
    ];

    final linhas = <List<String>>[header];

    for (final m in materiais) {
      linhas.add([
        m.materialCode,
        m.description,
        m.unidadeVenda ?? '',
        m.pesoUnidade?.toString() ?? '',
        m.pesoCaixa?.toString() ?? '',
        m.fatorConversao?.toStringAsFixed(4) ?? '',
        m.empresa ?? '',
        m.marca ?? '',
        m.gramatura ?? '',
        m.categoria ?? '',
        m.linha ?? '',
        m.agrupamentoPreco ?? '',
        m.cpvReais?.toStringAsFixed(4) ?? '',
        m.cpvPct?.toStringAsFixed(4) ?? '',
        m.deducoesPct?.toStringAsFixed(4) ?? '',
        m.deducoesReais?.toStringAsFixed(4) ?? '',
        m.despesasVarPct?.toStringAsFixed(4) ?? '',
        m.despesasVarReais?.toStringAsFixed(4) ?? '',
      ]);
    }

    final csv = linhas
        .map((row) {
          return row
              .map((cell) {
                // Escapa células com ponto-e-vírgula ou aspas
                if (cell.contains(';') ||
                    cell.contains('"') ||
                    cell.contains('\n')) {
                  return '"${cell.replaceAll('"', '""')}"';
                }
                return cell;
              })
              .join(';');
        })
        .join('\n');

    // BOM para Excel abrir UTF-8 corretamente
    final bom = [0xEF, 0xBB, 0xBF];
    final bytes = utf8.encode(csv);
    return Uint8List.fromList([...bom, ...bytes]);
  }

  // ── Upload e parse da planilha ──────────────────────────────────────────────

  /// Lê o CSV enviado pelo usuário e faz upsert em materials.
  /// Retorna { atualizados, erros, mensagensErro }
  Future<UploadResult> processarUpload(Uint8List bytes) async {
    // Remove BOM se existir
    final hasBom =
        bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;

    var content = utf8.decode(
      hasBom ? bytes.sublist(3) : bytes,
      allowMalformed: true,
    );

    // Remove \r para compatibilidade com arquivos gerados no Windows/Excel
    content = content.replaceAll('\r', '');

    final linhas = content
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (linhas.length < 2) {
      throw Exception('Planilha vazia ou sem dados além do cabeçalho.');
    }

    final header = _parseCsvLine(linhas[0]);
    final idx = _buildIndex(header);

    final erros = <String>[];
    final registros = <Map<String, dynamic>>[];

    for (var i = 1; i < linhas.length; i++) {
      final cols = _parseCsvLine(linhas[i]);
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

      void addNum(String col) {
        final v = _col(cols, idx, col);
        if (v.isNotEmpty) {
          final d = double.tryParse(v.replaceAll(',', '.'));
          if (d != null) rec[col] = d;
        }
      }

      addStr('empresa');
      addStr('marca');
      addStr('gramatura');
      addStr('categoria');
      addStr('linha');
      addStr('agrupamento_preco');
      addNum('cpv_reais');
      addNum('cpv_pct');
      addNum('deducoes_pct');
      addNum('deducoes_reais');
      addNum('despesas_var_pct');
      addNum('despesas_var_reais');

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
        'ded_pct': cellNum(row, idxDeducao),
        'dv_pct': cellNum(row, idxDespesa),
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

  // ── Leitura mínima de .xlsx (bypassa o parser de estilos, só extrai valores) ─

  /// Descompacta o .xlsx e lê a primeira planilha diretamente do XML
  /// (xl/worksheets/sheetN.xml + xl/sharedStrings.xml), sem depender de
  /// bibliotecas que tentam interpretar formatação/estilo de número.
  List<List<String>> _readXlsxRows(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? findFile(bool Function(String) match) {
      for (final f in archive.files) {
        if (f.isFile && match(f.name)) return f;
      }
      return null;
    }

    String xmlOf(ArchiveFile file) =>
        utf8.decode(file.content as List<int>, allowMalformed: true);

    // Shared strings (texto reaproveitado entre células)
    final sharedStrings = <String>[];
    final sharedStringsFile = findFile((n) => n == 'xl/sharedStrings.xml');
    if (sharedStringsFile != null) {
      final doc = XmlDocument.parse(xmlOf(sharedStringsFile));
      for (final si in doc.findAllElements('si')) {
        final texto = si.findElements('t').isNotEmpty
            ? si.findElements('t').first.innerText
            : si.findAllElements('t').map((t) => t.innerText).join();
        sharedStrings.add(texto);
      }
    }

    final sheetFiles =
        archive.files
            .where((f) => f.isFile &&
                RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final sheetFile = sheetFiles.isNotEmpty ? sheetFiles.first : null;
    if (sheetFile == null) {
      throw Exception('Nenhuma planilha encontrada dentro do arquivo .xlsx.');
    }

    final sheetDoc = XmlDocument.parse(xmlOf(sheetFile));
    final rows = <List<String>>[];

    for (final rowEl in sheetDoc.findAllElements('row')) {
      final rowValues = <String>[];
      for (final cellEl in rowEl.findElements('c')) {
        final ref = cellEl.getAttribute('r') ?? '';
        final colIndex = _xlsxColumnIndex(ref);

        String value = '';
        final type = cellEl.getAttribute('t');
        if (type == 's') {
          final v = cellEl.findElements('v');
          final i = v.isNotEmpty ? int.tryParse(v.first.innerText) : null;
          value = (i != null && i >= 0 && i < sharedStrings.length)
              ? sharedStrings[i]
              : '';
        } else if (type == 'inlineStr') {
          value = cellEl.findAllElements('t').map((t) => t.innerText).join();
        } else {
          final v = cellEl.findElements('v');
          value = v.isNotEmpty ? v.first.innerText : '';
        }

        while (rowValues.length <= colIndex) {
          rowValues.add('');
        }
        rowValues[colIndex] = value;
      }
      rows.add(rowValues);
    }

    return rows;
  }

  /// Converte uma referência de célula ("C5", "AB12") no índice de coluna
  /// 0-based ("C" → 2, "AB" → 27).
  int _xlsxColumnIndex(String cellRef) {
    var idx = 0;
    for (final char in cellRef.split('')) {
      final code = char.codeUnitAt(0);
      if (code < 65 || code > 90) break; // só letras (A-Z) contam
      idx = idx * 26 + (code - 64);
    }
    return idx - 1;
  }

  // ── CSV helpers ─────────────────────────────────────────────────────────────

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    var inQuotes = false;
    final current = StringBuffer();

    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (c == ';' && !inQuotes) {
        result.add(current.toString().trim());
        current.clear();
      } else {
        current.write(c);
      }
    }
    result.add(current.toString().trim());
    return result;
  }

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