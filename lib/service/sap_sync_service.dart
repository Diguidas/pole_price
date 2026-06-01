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
    String? databOp, // NOVO
    String? datbiOp, // NOVO
    String? matnr,
  }) async {
    final res = await supabase.functions.invoke(
      'swift-handler',
      body: {
        'pltyp': pltyp,
        if (datab != null) 'datab': datab,
        if (datbi != null) 'datbi': datbi,
        if (databOp != null) 'datab_op': databOp, // NOVO
        if (datbiOp != null) 'datbi_op': datbiOp, // NOVO
        if (matnr != null) 'matnr': matnr,
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
    String? databOp, // NOVO
    String? datbiOp,
  }) async {
    final res = await supabase.functions.invoke(
      'sync-price-group',
      body: {
        'pltyp': pltyp,
        'kdgrp': kdgrp,
        if (datab != null) 'datab': datab,
        if (datbi != null) 'datbi': datbi,
        if (databOp != null) 'datab_op': databOp, // NOVO
        if (datbiOp != null) 'datbi_op': datbiOp, // NOVO
      },
    );

    print('STATUS: ${res.status}');
    print('RAW TYPE: ${res.data.runtimeType}');
    print('RAW: ${res.data}');

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

  // ---------------------------------------------------------------------------
  // Mapeamento interno
  // ---------------------------------------------------------------------------

  Future<List<MaterialPreco>> _mapEntriesToMateriais(
    List<dynamic> entries, {
    String? datab,
    String? datbi,
    String? kdgrp,
  }) async {
    print('ENTRIES RECEBIDOS: ${entries.length}');
    final matnrs = <String>{};
    for (final entry in entries) {
      final _matRaw = entry['MATERIALS'] ?? entry['materials'];
      print('MATERIALS TYPE: ${_matRaw.runtimeType} | VALUE: $_matRaw');
      final materials = _matRaw is List ? _matRaw : <dynamic>[];
      print('MATERIALS LENGTH: ${materials.length}');
      for (final m in materials) {
        final matnr = (m['MATNR'] ?? m['matnr'])?.toString();
        if (matnr != null && matnr.isNotEmpty) {
          matnrs.add(matnr.replaceAll(RegExp(r'^0+'), ''));
        }
      }
    }

    print('MATNRS COLETADOS: $matnrs');
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

    // Busca CPV mais recente por material
    final costsRes = await supabase
        .from('product_costs')
        .select('product_code, cost_value, period')
        .inFilter('product_code', matnrs.toList())
        .order('period', ascending: false);

    final cpvMap = <String, double>{};
    for (final c in costsRes as List<dynamic>) {
      final code = c['product_code'].toString();
      if (!cpvMap.containsKey(code)) {
        cpvMap[code] = (c['cost_value'] as num).toDouble();
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
        // Depois:
        final kbetr = (m['KBETR'] ?? m['kbetr'])?.toString() ?? '0';
        final kgSugRaw = m['KG_SUG'] ?? m['kg_sug'] ?? m['KBPER'] ?? m['kbper'];
        final kgSug = kgSugRaw != null
            ? double.tryParse(kgSugRaw.toString())
            : null;

        result.add(
          MaterialPreco(
            codigo: matnr,
            description: product?['name']?.toString() ?? matnr,
            precoAtual: double.tryParse(kbetr) ?? 0,
            clusterId: product?['pricing_cluster_id']?.toString(),
            cpv: cpvMap[matnr],
            datab: entryDatab,
            datbi: entryDatbi,
            origemMaterial: OrigemMaterial.sap,
            kgSug: (kgSug != null && kgSug > 0) ? kgSug : null, // ← ADICIONADO
          ),
        );
      }
    }

    return result;
  }
}
