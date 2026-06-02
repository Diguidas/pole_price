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
    String? kznep,      // valor do filtro inativo: 'I' = inativo, null = sem filtro
    String? kznepOp,    // operador: 'EQ' = apenas inativos, 'NE' = excluir inativos
    String? loevm,      // valor do filtro bloqueado: 'X' = bloqueado, null = sem filtro
    String? loevmOp,    // operador: 'EQ' = apenas bloqueados, 'NE' = excluir bloqueados
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
        final kbetr = (m['KBETR'] ?? m['kbetr'])?.toString() ?? '0';
        final kgSugRaw = m['KG_SUG'] ?? m['kg_sug'] ?? m['KBPER'] ?? m['kbper'];
        final kgSug = kgSugRaw != null
            ? double.tryParse(kgSugRaw.toString())
            : null;

        // Campos necessários para push de volta ao SAP
        final konwa = (m['KONWA'] ?? m['konwa'])?.toString();
        final kmein = (m['KMEIN'] ?? m['kmein'])?.toString();
        final krech = (m['KRECH'] ?? m['krech'])?.toString();
        final mxwrtRaw = m['MXWRT'] ?? m['mxwrt'];
        final mxwrt = mxwrtRaw != null
            ? double.tryParse(mxwrtRaw.toString())
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
            kgSug: (kgSug != null && kgSug > 0) ? kgSug : null,
            konwa: konwa,
            kmein: kmein,
            krech: krech,
            mxwrt: mxwrt,
            bloqueado: _isX(m['LOEVM_KO'] ?? m['loevm_ko']),
            inativo: _isX(m['KZNEP'] ?? m['kznep']),
          ),
        );
      }
    }

    return result;
  }
}