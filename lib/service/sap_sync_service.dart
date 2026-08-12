import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/material_preco.dart';

/// Integração direta com SAP via Edge Functions.
///
/// Os preços NÃO são mais salvos no Supabase — são retornados em memória
/// e usados diretamente pelo PrecoController durante a sessão de edição.
class SapSyncService {
  final SupabaseClient supabase;

  SapSyncService(this.supabase);

  /// Busca preços ao vivo do SAP pela action 'lista' (A913).
  Future<List<MaterialPreco>> fetchFromSapLista({
    required String pltyp,
    String? datab,
    String? datbi,
    String? databOp,
    String? datbiOp,
    String? matnr,
    String? kznep, // valor do filtro inativo: 'I' = inativo, null = sem filtro
    String?
    kznepOp, // operador: 'EQ' = apenas inativos, 'NE' = excluir inativos
    String?
    loevm, // valor do filtro bloqueado: 'X' = bloqueado, null = sem filtro
    String?
    loevmOp, // operador: 'EQ' = apenas bloqueados, 'NE' = excluir bloqueados
  }) async {
    final res = await supabase.functions.invoke(
      'swift-handler',
      body: {
        'pltyp': pltyp,
        if (datab != null) 'datab': datab,
        if (datbi != null) 'datbi': datbi,
        if (databOp != null) 'datab_op': databOp,
        if (datbiOp != null) 'datbi_op': datbiOp,
        if (matnr != null) 'matnr': matnr,
        if (kznep != null) 'kznep': kznep,
        if (kznepOp != null) 'kznep_op': kznepOp,
        if (loevm != null) 'loevm_ko': loevm,
        if (loevmOp != null) 'loevm_ko_op': loevmOp,
      },
    );

    if (res.status == 204) return [];
    if (res.status != 200) {
      throw Exception('Falha ao buscar lista SAP (${res.status}): ${res.data}');
    }

    final raw = res.data;
    final entries = raw is List
        ? raw
        : (raw['data'] ?? raw['items'] ?? raw['listas'] ?? raw['results'] ?? [])
              as List;

    return _mapEntriesToMateriais(
      entries.cast<dynamic>(),
      pltyp: pltyp,
      datab: datab,
      datbi: datbi,
    );
  }

  /// Busca preços ao vivo do SAP pela action 'grupo' (A912).
  Future<List<MaterialPreco>> fetchFromSapGrupo({
    required String pltyp,
    required String kdgrp,
    String? datab,
    String? datbi,
    String? databOp,
    String? datbiOp,
    String? kznep,
    String? kznepOp,
    String? loevm,
    String? loevmOp,
  }) async {
    final res = await supabase.functions.invoke(
      'sync-price-group',
      body: {
        'pltyp': pltyp,
        'kdgrp': kdgrp,
        if (datab != null) 'datab': datab,
        if (datbi != null) 'datbi': datbi,
        if (databOp != null) 'datab_op': databOp,
        if (datbiOp != null) 'datbi_op': datbiOp,
        if (kznep != null) 'kznep': kznep,
        if (kznepOp != null) 'kznep_op': kznepOp,
        if (loevm != null) 'loevm_ko': loevm,
        if (loevmOp != null) 'loevm_ko_op': loevmOp,
      },
    );

    if (res.status == 204) return [];
    if (res.status != 200) {
      throw Exception('Falha ao buscar grupo SAP (${res.status}): ${res.data}');
    }

    final raw = res.data;
    List<dynamic> entries = [];
    if (raw is List) {
      entries = raw;
    } else if (raw is Map) {
      final val = raw['data'] ?? raw['items'] ?? raw['results'];
      if (val is List) entries = val;
    }

    return _mapEntriesToMateriais(
      entries.cast<dynamic>(),
      pltyp: pltyp,
      datab: datab,
      datbi: datbi,
      kdgrp: kdgrp,
    );
  }

  /// Envia preços aprovados do Supabase para o SAP (comportamento inalterado).
  Future<void> pushToSap({required String draftId}) async {
    final res = await supabase.functions.invoke(
      'push-sap-prices',
      body: {'draft_id': draftId},
    );

    if (res.status != 200) {
      throw Exception(
        'Falha ao enviar preços ao SAP (${res.status}): ${res.data}',
      );
    }
  }

  /// Busca o histórico de preços de um ou mais materiais via action "historico".
  Future<List<Map<String, dynamic>>> fetchHistoricoRaw({
    required List<String> matnrs,
    String? datab,
    String? datbi,
    String? databOp,
    String? datbiOp,
  }) async {
    if (matnrs.isEmpty) return [];

    final body = <String, dynamic>{
      'materials': matnrs.map((m) => {'matnr': m}).toList(),
      if (datab != null) 'datab': datab,
      if (datab != null) 'datab_op': databOp ?? 'GE',
      if (datbi != null) 'datbi': datbi,
      if (datbi != null) 'datbi_op': datbiOp ?? 'LE',
    };

    final res = await supabase.functions.invoke(
      'get-price-historic',
      body: body,
    );

    if (res.status == 204) return [];
    if (res.status != 200) {
      throw Exception(
        'Falha ao buscar histórico SAP (${res.status}): ${res.data}',
      );
    }

    final raw = res.data;
    List<dynamic> data = [];
    if (raw is List) {
      data = raw;
    } else if (raw is Map) {
      final val = raw['data'];
      if (val is List) data = val;
    }

    return data.whereType<Map<String, dynamic>>().toList();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Interpreta valores SAP que significam "marcado": 'X', 'x', 'I', true, '1', 1
  /// KZNEP usa 'I' para inativo; LOEVM_KO usa 'X' para bloqueado.
  static bool _isX(dynamic v) {
    if (v == null) return false;
    final s = v.toString().trim().toUpperCase();
    return s == 'X' || s == 'I' || s == '1' || s == 'TRUE';
  }

  // ---------------------------------------------------------------------------
  // Mapeamento interno
  // ---------------------------------------------------------------------------

  Future<List<MaterialPreco>> _mapEntriesToMateriais(
    List<dynamic> entries, {
    String? pltyp,
    String? datab,
    String? datbi,
    String? kdgrp,
  }) async {
    final matnrs = <String>{};
    for (final entry in entries) {
      final _matRaw = entry['MATERIALS'] ?? entry['materials'];
      final materials = _matRaw is List ? _matRaw : <dynamic>[];
      for (final m in materials) {
        final matnr = (m['MATNR'] ?? m['matnr'])?.toString();
        if (matnr != null && matnr.isNotEmpty) {
          matnrs.add(matnr.replaceAll(RegExp(r'^0+'), ''));
        }
      }
    }

    if (matnrs.isEmpty) return [];

    // Busca descrições em products
    final productsRes = await supabase
        .from('products')
        .select('code, name, pricing_cluster_id')
        .inFilter('code', matnrs.toList());

    final productMap = <String, Map<String, dynamic>>{
      for (final p in productsRes as List<dynamic>)
        p['code'].toString(): p as Map<String, dynamic>,
    };

    // Busca peso da embalagem/caixa (necessário para PPV/KG e MC Pole) e o
    // vínculo de preço pai/filho + agrupamento — são atributos do material,
    // não da lista de preço.
    final pesoRes = await supabase
        .from('materials')
        .select(
          'material_code, peso_unidade, peso_caixa, '
          'agrupamento_preco, material_pai_code, excecao_preco_pct',
        )
        .inFilter('material_code', matnrs.toList());

    final pesoMap = <String, Map<String, dynamic>>{
      for (final p in pesoRes as List<dynamic>)
        p['material_code'].toString(): p as Map<String, dynamic>,
    };

    // Busca PPC do ciclo aprovado mais recente (histórico), por lista
    final ppcHistoricoMap = <String, double>{};
    if (pltyp != null) {
      final ppcRes = await supabase
          .from('ppc_historico')
          .select('product_code, ppc')
          .eq('pltyp', pltyp)
          .inFilter('product_code', matnrs.toList());
      for (final p in ppcRes as List<dynamic>) {
        final code = p['product_code']?.toString();
        final ppc = p['ppc'] != null
            ? double.tryParse(p['ppc'].toString())
            : null;
        if (code != null && ppc != null) ppcHistoricoMap[code] = ppc;
      }
    }

    // Busca CPV/Ded%/DV% mais recentes por material
    final costsRes = await supabase
        .from('product_costs')
        .select('product_code, cost_value, ded_pct, dv_pct, period')
        .inFilter('product_code', matnrs.toList());

    // 'period' é texto e convive com formatos legados ('MANUAL', '2025.05')
    // que "vencem" um período real (ex: '202607') em ordenação alfabética —
    // só considera o formato AAAAMM (6 dígitos) para decidir o mais recente.
    final periodoRegex = RegExp(r'^\d{6}$');
    final melhorPeriodoPorCodigo = <String, String>{};
    for (final c in costsRes as List<dynamic>) {
      final code = c['product_code'].toString();
      final periodo = c['period']?.toString();
      if (periodo == null || !periodoRegex.hasMatch(periodo)) continue;
      final atual = melhorPeriodoPorCodigo[code];
      if (atual == null || periodo.compareTo(atual) > 0) {
        melhorPeriodoPorCodigo[code] = periodo;
      }
    }

    final cpvMap = <String, double>{};
    final dedMap = <String, double>{};
    final dvMap = <String, double>{};
    for (final c in costsRes) {
      final code = c['product_code'].toString();
      final periodo = c['period']?.toString();
      if (periodo == null || periodo != melhorPeriodoPorCodigo[code]) continue;
      if (cpvMap.containsKey(code)) continue; // já preenchido para este período
      if (c['cost_value'] != null) {
        cpvMap[code] = (c['cost_value'] as num).toDouble();
      }
      if (c['ded_pct'] != null) {
        dedMap[code] = (c['ded_pct'] as num).toDouble();
      }
      if (c['dv_pct'] != null) {
        dvMap[code] = (c['dv_pct'] as num).toDouble();
      }
    }

    // Busca margemFlat e margemOferta via price_lists → pricing_policies
    double? margemFlat;
    double? margemOferta;
    if (pltyp != null) {
      try {
        final listRes = await supabase
            .from('price_lists')
            .select('policy_id, pricing_policies(margem_flat, margem_oferta)')
            .eq('pltyp', pltyp)
            .maybeSingle();
        if (listRes != null) {
          final policy = listRes['pricing_policies'] as Map<String, dynamic>?;
          margemFlat = policy?['margem_flat'] != null
              ? double.tryParse(policy!['margem_flat'].toString())
              : null;
          margemOferta = policy?['margem_oferta'] != null
              ? double.tryParse(policy!['margem_oferta'].toString())
              : null;
        }
      } catch (_) {
        // Margens não encontradas — continua sem elas
      }
    }

    // Monta a lista final
    final result = <MaterialPreco>[];
    for (final entry in entries) {
      final entryDatab = (entry['DATAB'] ?? entry['datab'])?.toString();
      final entryDatbi = (entry['DATBI'] ?? entry['datbi'])?.toString();
      final _matRaw2 = entry['MATERIALS'] ?? entry['materials'];
      final materials = _matRaw2 is List ? _matRaw2 : <dynamic>[];
      for (final m in materials) {
        final matnrRaw = (m['MATNR'] ?? m['matnr'])?.toString() ?? '';
        if (matnrRaw.isEmpty) continue;

        final matnr = matnrRaw.replaceAll(RegExp(r'^0+'), '');
        final product = productMap[matnr];
        final kbetr = (m['KBETR'] ?? m['kbetr'])?.toString() ?? '0';
        final kgSugRaw = m['KG_SUG'] ?? m['kg_sug'] ?? m['KBPER'] ?? m['kbper'];
        final kgSug = kgSugRaw != null
            ? double.tryParse(kgSugRaw.toString())
            : null;

        // Campos necessários para push de volta ao SAP
        final konwa = (m['KONWA'] ?? m['konwa'])?.toString();
        final kmein = (m['KMEIN'] ?? m['kmein'])?.toString();
        final krech = (m['KRECH'] ?? m['krech'])?.toString();
        // MXWRT/GKWRT NÃO são lidos do SAP aqui de propósito: são limites
        // editáveis só pelo pop-up "Limites SAP" no app. Se o material já
        // tiver esses valores gravados na condição do SAP, eles não devem
        // aparecer sozinhos sem o usuário ter passado pelo pop-up nesta
        // sessão — evita mandar um limite "meio" preenchido de volta.
        final peso = pesoMap[matnr];

        result.add(
          MaterialPreco(
            codigo: matnr,
            description: product?['name']?.toString() ?? matnr,
            precoAtual: double.tryParse(kbetr) ?? 0,
            clusterId: product?['pricing_cluster_id']?.toString(),
            cpv: cpvMap[matnr],
            dedPct: dedMap[matnr],
            dvPct: dvMap[matnr],
            margemFlat: margemFlat,
            margemOferta: margemOferta,
            ppcHistorico: ppcHistoricoMap[matnr],
            datab: entryDatab,
            datbi: entryDatbi,
            origemMaterial: OrigemMaterial.sap,
            kgSug: (kgSug != null && kgSug > 0) ? kgSug : null,
            pesoUnidade: peso?['peso_unidade'] != null
                ? double.tryParse(peso!['peso_unidade'].toString())
                : null,
            pesoCaixa: peso?['peso_caixa'] != null
                ? double.tryParse(peso!['peso_caixa'].toString())
                : null,
            agrupamentoPreco: peso?['agrupamento_preco']?.toString(),
            materialPaiCode: peso?['material_pai_code']?.toString(),
            excecaoPrecoPct: peso?['excecao_preco_pct'] != null
                ? double.tryParse(peso!['excecao_preco_pct'].toString())
                : null,
            konwa: konwa,
            kmein: kmein,
            krech: krech,
            bloqueado: _isX(m['LOEVM_KO'] ?? m['loevm_ko']),
            inativo: _isX(m['KZNEP'] ?? m['kznep']),
          ),
        );
      }
    }

    return result;
  }
}
