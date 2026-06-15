// lib/service/materials_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pole_price/models/material/material_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MaterialsService {
  final SupabaseClient supabase;

  MaterialsService(this.supabase);

  // ── Listar materiais ────────────────────────────────────────────────────────

  /// Busca todos os materiais da tabela materials (view materials_full se existir).
  Future<List<MaterialSap>> listar({
    String? busca,
    String? empresa,
    String? marca,
  }) async {
    var query = supabase.from('materials').select().order('description');

    final res = await query;
    final lista = (res as List)
        .map((j) => MaterialSap.fromJson(j as Map<String, dynamic>))
        .toList();

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