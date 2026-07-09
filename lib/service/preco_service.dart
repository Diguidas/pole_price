import 'package:pole_price/models/material_preco.dart';
import 'package:pole_price/models/pricelist_model.dart';
import 'package:pole_price/models/pricing_cluster_item.dart';
import 'package:pole_price/models/regra_ajuste.dart';
import 'package:pole_price/service/draft_pricing_service.dart';
import 'package:pole_price/service/sap_sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PriceService {
  final SupabaseClient supabase;
  late final DraftPricingService draftPricing;
  late final SapSyncService sapSync;

  PriceService(this.supabase) {
    draftPricing = DraftPricingService(supabase);
    sapSync = SapSyncService(supabase);
  }

  Future<List<PriceList>> getLists() async {
    final res = await supabase
        .from('price_lists')
        .select('pltyp, ptext')
        .order('ptext');
    return (res as List).map((e) => PriceList.fromJson(e)).toList();
  }

  Future<List<MaterialPreco>> getMaterials(String listId) async {
    final listFuture = supabase
        .from('price_lists')
        .select('margem_flat, margem_oferta')
        .eq('id', listId)
        .single();

    // Não ordena por 'period' direto: a coluna é texto e convive com formatos
    // legados ('MANUAL', '2025.05') que "vencem" um período real (ex: '202607')
    // em ordenação alfabética. Só considera períodos no formato AAAAMM (6
    // dígitos) e escolhe o maior numericamente.
    final periodFuture = supabase.from('product_costs').select('period');

    // ← Adicionado: peso_unidade, peso_caixa, unidade_venda
    final matsFuture = supabase
        .from('materials')
        .select('product_id, description, price, peso_unidade, peso_caixa, unidade_venda')
        .eq('price_list_id', listId);

    final round1 = await Future.wait<dynamic>([
      listFuture,
      periodFuture,
      matsFuture,
    ]);

    final listRes = round1[0] as Map<String, dynamic>;
    final periodRes = round1[1] as List;
    final matsRes = round1[2] as List;

    final margemFlat = listRes['margem_flat'] != null
        ? double.tryParse(listRes['margem_flat'].toString())
        : null;
    final margemOferta = listRes['margem_oferta'] != null
        ? double.tryParse(listRes['margem_oferta'].toString())
        : null;

    final periodoRegex = RegExp(r'^\d{6}$');
    final latestPeriod = periodRes
        .map((r) => r['period']?.toString())
        .whereType<String>()
        .where((p) => periodoRegex.hasMatch(p))
        .fold<String?>(null, (max, p) => (max == null || p.compareTo(max) > 0) ? p : max);

    if (matsRes.isEmpty) return [];

    final codes = matsRes
        .map((m) => m['product_id']?.toString())
        .whereType<String>()
        .toList();

    // classification não é mais usada como filtro: desde que o import de
    // custos passou a vir só da planilha (CPV/Ded%/DV% por período), toda
    // linha de product_costs do período mais recente é válida.
    final Future<dynamic> cpvFuture = latestPeriod != null && codes.isNotEmpty
        ? supabase
              .from('product_costs')
              .select('product_code, cost_value, ded_pct, dv_pct')
              .eq('period', latestPeriod)
              .inFilter('product_code', codes)
        : Future<dynamic>.value(<dynamic>[]);

    final Future<dynamic> clusterFuture = codes.isNotEmpty
        ? supabase
              .from('products')
              .select('code, pricing_cluster_id')
              .inFilter('code', codes)
        : Future<dynamic>.value(<dynamic>[]);

    // Vínculo de preço pai/filho + agrupamento — atributo do material (tabela
    // materials, tela de Materiais), não da lista, então busca por
    // material_code sem filtrar por price_list_id.
    final Future<dynamic> vinculoFuture = codes.isNotEmpty
        ? supabase
              .from('materials')
              .select('material_code, agrupamento_preco, material_pai_code, excecao_preco_pct')
              .inFilter('material_code', codes)
        : Future<dynamic>.value(<dynamic>[]);

    final round2 = await Future.wait<dynamic>([
      cpvFuture,
      clusterFuture,
      vinculoFuture,
    ]);

    final cpvRes = round2[0] as List;
    final prodRes = round2[1] as List;
    final vinculoRes = round2[2] as List;

    final Map<String, double> cpvMap = {};
    final Map<String, double> dedMap = {};
    final Map<String, double> dvMap = {};
    for (final row in cpvRes) {
      final code = row['product_code']?.toString();
      if (code == null) continue;
      final cost = row['cost_value'] != null
          ? double.tryParse(row['cost_value'].toString())
          : null;
      if (cost != null) cpvMap[code] = cost;
      final ded = row['ded_pct'] != null
          ? double.tryParse(row['ded_pct'].toString())
          : null;
      if (ded != null) dedMap[code] = ded;
      final dv = row['dv_pct'] != null
          ? double.tryParse(row['dv_pct'].toString())
          : null;
      if (dv != null) dvMap[code] = dv;
    }

    final Map<String, String> clusterMap = {};
    for (final row in prodRes) {
      final code = row['code']?.toString();
      final clusterId = row['pricing_cluster_id']?.toString();
      if (code != null && clusterId != null) clusterMap[code] = clusterId;
    }

    final Map<String, String> agrupamentoMap = {};
    final Map<String, String> paiMap = {};
    final Map<String, double> excecaoMap = {};
    for (final row in vinculoRes) {
      final code = row['material_code']?.toString();
      if (code == null) continue;
      final agr = row['agrupamento_preco']?.toString();
      if (agr != null) agrupamentoMap[code] = agr;
      final pai = row['material_pai_code']?.toString();
      if (pai != null) paiMap[code] = pai;
      final exc = row['excecao_preco_pct'] != null
          ? double.tryParse(row['excecao_preco_pct'].toString())
          : null;
      if (exc != null) excecaoMap[code] = exc;
    }

    return matsRes.map((m) {
      final code = m['product_id']?.toString() ?? '';
      final double precoTratado = m['price'] != null
          ? double.tryParse(m['price'].toString()) ?? 0.0
          : 0.0;
      return MaterialPreco(
        codigo: code,
        description: m['description'] ?? '',
        precoAtual: precoTratado,
        cpv: cpvMap[code],
        dedPct: dedMap[code],
        dvPct: dvMap[code],
        margemFlat: margemFlat,
        margemOferta: margemOferta,
        clusterId: clusterMap[code],
        agrupamentoPreco: agrupamentoMap[code],
        materialPaiCode: paiMap[code],
        excecaoPrecoPct: excecaoMap[code],
        // ← Novos campos de dimensionamento
        pesoUnidade: m['peso_unidade'] != null
            ? double.tryParse(m['peso_unidade'].toString())
            : null,
        pesoCaixa: m['peso_caixa'] != null
            ? double.tryParse(m['peso_caixa'].toString())
            : null,
        unidadeVenda: m['unidade_venda']?.toString(),
        bloqueado: false,
        inativo: false,
      );
    }).toList();
  }

  Future<void> updatePricesInSupabase({
    required String listId,
    required List<MaterialPreco> materiais,
  }) async {
    final alterados = materiais
        .where((m) => m.novoPreco > 0 && m.novoPreco != m.precoAtual)
        .toList();
    if (alterados.isEmpty) return;

    final codigosAlterados = alterados.map((m) => m.codigo).toList();

    final rows = await supabase
        .from('materials')
        .select('id, product_id')
        .eq('price_list_id', listId)
        .inFilter('product_id', codigosAlterados);

    final idPorProduto = <String, String>{};
    for (final row in rows as List) {
      final pid = row['product_id']?.toString();
      final id = row['id']?.toString();
      if (pid != null && id != null) idPorProduto[pid] = id;
    }

    final upsertRows = <Map<String, dynamic>>[];
    for (final m in alterados) {
      final rowId = idPorProduto[m.codigo] ?? idPorProduto[m.codigo.trim()];
      if (rowId == null) continue;
      upsertRows.add({'id': rowId, 'price': m.novoPreco, 'is_fixed': true});
    }

    if (upsertRows.isNotEmpty) {
      await supabase.from('materials').upsert(upsertRows);
    }
  }

  Future<List<PricingClusterItem>> getClusters() async {
    final res = await supabase
        .from('pricing_clusters')
        .select('id, name')
        .order('name');
    return (res as List).map((e) => PricingClusterItem.fromJson(e)).toList();
  }

  Future<List<MaterialPreco>> getMaterialsByCluster(String clusterId) async {
    final res = await supabase
        .from('products')
        .select('code, name')
        .eq('pricing_cluster_id', clusterId)
        .order('name');
    return (res as List).map((p) {
      return MaterialPreco(
        codigo: p['code'] ?? '',
        description: p['name'] ?? '',
        precoAtual: 0,
        clusterId: clusterId,
        bloqueado: false,
        inativo: false,
      );
    }).toList();
  }

  Future<String> saveDraft({
    String? draftId,
    required String? masterListId,
    required List<MaterialPreco> materiais,
    required List<String> targets,
    required List<RegraAjuste> regras,
    String? modo,
    String? kdgrp,
    String? vigenciaDatab,
    String? vigenciaDatbi,
    String? justificativa,
    String sapStatus = '',
    String draftStatus = 'pending',
  }) async {
    final userEmail = supabase.auth.currentUser?.email ?? 'desconhecido';

    late String resolvedId;

    if (draftId != null) {
      await supabase
          .from('price_drafts')
          .update({
            'status': draftStatus,
            'vigencia_datab': vigenciaDatab,
            'vigencia_datbi': vigenciaDatbi,
            if (justificativa != null && justificativa.isNotEmpty)
              'justificativa': justificativa,
          })
          .eq('id', draftId);

      await Future.wait([
        supabase.from('price_draft_items').delete().eq('draft_id', draftId),
        supabase.from('price_draft_targets').delete().eq('draft_id', draftId),
        supabase.from('price_draft_exceptions').delete().eq('draft_id', draftId),
      ]);

      resolvedId = draftId;
    } else {
      final draft = await supabase
          .from('price_drafts')
          .insert({
            'master_list_id': masterListId,
            'status': draftStatus,
            'created_by_email': userEmail,
            'vigencia_datab': vigenciaDatab,
            'vigencia_datbi': vigenciaDatbi,
            if (justificativa != null && justificativa.isNotEmpty)
              'justificativa': justificativa,
          })
          .select()
          .single();

      resolvedId = draft['id']?.toString() ?? '';
      if (resolvedId.isEmpty) throw Exception('Falha ao criar rascunho.');
    }

    final itens = materiais
        .where((m) => !m.removido)
        .map(
          (m) => {
            'draft_id': resolvedId,
            'product_id': m.codigo.trim(),
            'old_price': m.precoAtual,
            'new_price': m.novoPreco > 0 ? m.novoPreco : m.precoAtual,
            'price_edited': m.novoPreco > 0,
            'margin_pct': m.margemReal,
            'datab': vigenciaDatab ?? m.datab,
            'datbi': vigenciaDatbi ?? m.datbi,
            'kdgrp': kdgrp,
            'modo': modo,
            'origem_material': m.origemMaterial == OrigemMaterial.manual ? 'manual' : 'sap',
            'konwa': m.konwa,
            'kmein': m.kmein,
            'krech': m.krech,
            'mxwrt': m.mxwrt,
            'sap_status': sapStatus,
            'cpv': m.cpv,
            'kg_sug': m.kgSug,
            // ← Persiste overrides de sessão junto com o draft
            'ppc_novo': m.ppcNovoOverride,
            'ppc_oferta': m.ppcOfertaOverride,
            'margem_flat_override': m.margemFlatOverride,
            'margem_oferta_override': m.margemOfertaOverride,
          },
        )
        .toList();

    final targetRows = targets
        .map((e) => {'draft_id': resolvedId, 'target_list_id': e})
        .toList();

    final excRows = regras
        .map(
          (r) => {
            'draft_id': resolvedId,
            'target_list_id': r.targetListId,
            'level': _mapNivel(r.nivel),
            'adjust_type': _mapTipo(r.tipo),
            'value': r.valor,
            'cluster_id': r.clusterId,
            'material_id': r.materialId,
            'reference_desc': r.nivel == 'Grupo'
                ? r.clusterNome
                : r.nivel == 'Material'
                    ? r.materialNome
                    : null,
          },
        )
        .toList();

    final insertFutures = <Future<dynamic>>[];
    if (itens.isNotEmpty) {
      insertFutures.add(supabase.from('price_draft_items').insert(itens));
    }
    if (targetRows.isNotEmpty) {
      insertFutures.add(supabase.from('price_draft_targets').insert(targetRows));
    }
    if (excRows.isNotEmpty) {
      insertFutures.add(supabase.from('price_draft_exceptions').insert(excRows));
    }
    if (insertFutures.isNotEmpty) {
      await Future.wait<dynamic>(insertFutures);
    }

    return resolvedId;
  }

  Future<void> approveDraft(String draftId) async {
    await draftPricing.applyDraft(draftId);
  }

  String _mapNivel(String n) {
    switch (n) {
      case 'Grupo':    return 'material_group';
      case 'Material': return 'specific_material';
      default:         return 'full_table';
    }
  }

  Future<void> sincronizarCatalogo() async {
    final res = await supabase.functions.invoke('sync-price-catalog');
    if (res.status != 200) {
      throw Exception('Falha ao sincronizar catálogo SAP (${res.status})');
    }
  }

  String _mapTipo(String t) => t == 'Fixo' ? 'fixed' : 'percentual';
}