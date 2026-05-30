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
        .select()
        .order('description');

    return (res as List).map((e) => PriceList.fromJson(e)).toList();
  }

  /// Carrega materiais e preços **somente do Supabase** (`materials.price`).
  /// Não chama SAP. Use [syncFromSap] apenas quando o usuário clicar em "Buscar do SAP".
  Future<List<MaterialPreco>> getMaterials(String listId) async {
    // 1. Busca as margens da política vinculada à lista
    final listRes = await supabase
        .from('price_lists')
        .select('margem_flat, margem_oferta')
        .eq('id', listId)
        .single();

    final margemFlat = listRes['margem_flat'] != null
        ? double.tryParse(listRes['margem_flat'].toString())
        : null;

    final margemOferta = listRes['margem_oferta'] != null
        ? double.tryParse(listRes['margem_oferta'].toString())
        : null;

    // 2. Busca o período mais recente disponível no product_costs
    final periodRes = await supabase
        .from('product_costs')
        .select('period')
        .order('period', ascending: false)
        .limit(1)
        .maybeSingle();

    final latestPeriod = periodRes?['period'] as String?;

    // 3. Busca os materiais da lista — chave correta é product_id
    final matsRes = await supabase
        .from('materials')
        .select('product_id, description, price')
        .eq('price_list_id', listId);

    final materiais = matsRes as List;

    if (materiais.isEmpty) return [];

    final codes = materiais
        .map((m) => m['product_id']?.toString())
        .whereType<String>()
        .toList();

    // 4. Busca CPV em batch (tabela product_costs -> coluna cost_value é numeric)
    Map<String, double> cpvMap = {};
    if (latestPeriod != null && codes.isNotEmpty) {
      final cpvRes = await supabase
          .from('product_costs')
          .select('product_code, cost_value')
          .eq('period', latestPeriod)
          .eq('classification', 'Real')
          .inFilter('product_code', codes);

      for (final row in cpvRes as List) {
        final code = row['product_code']?.toString();
        final cost = row['cost_value'] != null
            ? double.tryParse(row['cost_value'].toString())
            : null;
        if (code != null && cost != null) {
          cpvMap[code] = cost;
        }
      }
    }

    // 5. Busca cluster_id dos produtos na tabela 'products' (onde a coluna é 'code')
    Map<String, String> clusterMap = {};
    if (codes.isNotEmpty) {
      final prodRes = await supabase
          .from('products')
          .select('code, pricing_cluster_id')
          .inFilter('code', codes);

      for (final row in prodRes as List) {
        final code = row['code']?.toString();
        final clusterId = row['pricing_cluster_id']?.toString();
        if (code != null && clusterId != null) {
          clusterMap[code] = clusterId;
        }
      }
    }

    // 6. Monta os objetos convertendo com segurança o numeric do Postgres
    return materiais.map((m) {
      final code = m['product_id']?.toString() ?? '';

      // Garante que o numeric 'price' do banco mude para double sem crashar se vier como String
      final double precoTratado = m['price'] != null
          ? double.tryParse(m['price'].toString()) ?? 0.0
          : 0.0;

      return MaterialPreco(
        codigo: code,
        description: m['description'] ?? '',
        precoAtual: precoTratado,
        cpv: cpvMap[code],
        margemFlat: margemFlat,
        margemOferta: margemOferta,
        clusterId:
            clusterMap[code], // Vincula o cluster vindo da tabela de produtos
      );
    }).toList();
  }

  /// Atualiza os preços editados na tela de Preço de volta ao Supabase (tabela materials).
  Future<void> updatePricesInSupabase({
    required String listId,
    required List<MaterialPreco> materiais,
  }) async {
    final alterados = materiais
        .where((m) => m.novoPreco > 0 && m.novoPreco != m.precoAtual)
        .toList();
    if (alterados.isEmpty) return;

    final rows = await supabase
        .from('materials')
        .select('id, product_id')
        .eq('price_list_id', listId);

    final idPorProduto = <String, String>{};
    for (final row in rows as List) {
      final pid = row['product_id']?.toString();
      final id = row['id']?.toString();
      if (pid != null && id != null) idPorProduto[pid] = id;
    }

    for (final m in alterados) {
      final rowId = idPorProduto[m.codigo] ?? idPorProduto[m.codigo.trim()];
      if (rowId == null) continue;
      await supabase.from('materials').update({
        'price': m.novoPreco,
        'is_fixed': true,
      }).eq('id', rowId);
    }
  }

  /// Lista todos os clusters para o dropdown de Exceções
  Future<List<PricingClusterItem>> getClusters() async {
    final res = await supabase
        .from('pricing_clusters')
        .select('id, name')
        .order('name');

    return (res as List).map((e) => PricingClusterItem.fromJson(e)).toList();
  }

  /// Lista materiais de um cluster específico (para dropdown nível Material)
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
      );
    }).toList();
  }

  Future<String> saveDraft({
    required String? masterListId,
    required List<MaterialPreco> materiais,
    required List<String> targets,
    required List<RegraAjuste> regras,
  }) async {
    final draft = await supabase
        .from('price_drafts')
        .insert({'master_list_id': masterListId, 'status': 'pending'})
        .select()
        .single();

    final draftId = draft['id']?.toString() ?? '';
    if (draftId.isEmpty) {
      throw Exception('Falha ao criar rascunho de aprovação.');
    }

    final itens = materiais
        .where((m) => m.novoPreco > 0 && m.novoPreco != m.precoAtual)
        .map(
          (m) => {
            'draft_id': draftId,
            'product_id': m.codigo.trim(),
            'old_price': m.precoAtual,
            'new_price': m.novoPreco,
            'margin_pct': m.margemReal,
          },
        )
        .toList();

    if (itens.isNotEmpty) {
      await supabase.from('price_draft_items').insert(itens);
    }

    final t = targets
        .map((e) => {'draft_id': draftId, 'target_list_id': e})
        .toList();

    if (t.isNotEmpty) {
      await supabase.from('price_draft_targets').insert(t);
    }

    final exc = regras.map((r) {
      return {
        'draft_id': draftId,
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
      };
    }).toList();

    if (exc.isNotEmpty) {
      await supabase.from('price_draft_exceptions').insert(exc);
    }

    return draftId;
  }

  /// Aprova o draft: atualiza Supabase e envia ao SAP.
  Future<void> approveDraft(String draftId) async {
    await draftPricing.applyDraft(draftId);
    await sapSync.pushToSap(draftId: draftId);
  }

  /// Puxa preços do SAP para o Supabase (botão manual na tela de preço).
  Future<SapSyncResult> syncFromSap({String? listId}) =>
      sapSync.syncFromSap(listId: listId);

  String _mapNivel(String n) {
    switch (n) {
      case 'Grupo':
        return 'material_group';
      case 'Material':
        return 'specific_material';
      default:
        return 'full_table';
    }
  }

  String _mapTipo(String t) => t == 'Fixo' ? 'fixed' : 'percentual';
}
