import 'package:pole_price/models/material_preco.dart';
import 'package:pole_price/models/pricelist_model.dart';
import 'package:pole_price/models/pricing_cluster_item.dart';
import 'package:pole_price/models/regra_ajuste.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PriceService {
  final SupabaseClient supabase;

  PriceService(this.supabase);

  Future<List<PriceList>> getLists() async {
    final res = await supabase
        .from('price_lists')
        .select()
        .order('description');

    return (res as List).map((e) => PriceList.fromJson(e)).toList();
  }

  Future<List<MaterialPreco>> getMaterials(String listId) async {
    // 1. Busca as margens da política vinculada à lista
    final listRes = await supabase
        .from('price_lists')
        .select('margem_flat, margem_oferta')
        .eq('id', listId)
        .single();

    final margemFlat = (listRes['margem_flat'] as num?)?.toDouble();
    final margemOferta = (listRes['margem_oferta'] as num?)?.toDouble();

    // 2. Busca o período mais recente disponível no product_costs
    final periodRes = await supabase
        .from('product_costs')
        .select('period')
        .order('period', ascending: false)
        .limit(1)
        .maybeSingle();

    final latestPeriod = periodRes?['period'] as String?;

    // 3. Busca os materiais da lista
    final matsRes = await supabase
        .from('materials')
        .select()
        .eq('price_list_id', listId);

    final materiais = matsRes as List;

    if (materiais.isEmpty) return [];

    // 4. Busca CPV em batch
    Map<String, double> cpvMap = {};

    if (latestPeriod != null) {
      final codes = materiais
          .map((m) => m['product_id']?.toString())
          .whereType<String>()
          .toList();

      if (codes.isNotEmpty) {
        final cpvRes = await supabase
            .from('product_costs')
            .select('product_code, cost_value')
            .eq('period', latestPeriod)
            .eq('classification', 'Real')
            .inFilter('product_code', codes);

        for (final row in cpvRes as List) {
          final code = row['product_code']?.toString();
          final cost = (row['cost_value'] as num?)?.toDouble();
          if (code != null && cost != null) {
            cpvMap[code] = cost;
          }
        }
      }
    }

    // 5. Busca cluster_id dos produtos para permitir filtro por cluster
    final codes = materiais
        .map((m) => m['product_id']?.toString())
        .whereType<String>()
        .toList();

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

    // 6. Monta os MaterialPreco
    return materiais.map((m) {
      final code = m['product_id']?.toString() ?? '';
      return MaterialPreco(
        codigo: code,
        description: m['description'] ?? '',
        precoAtual: (m['price'] as num).toDouble(),
        cpv: cpvMap[code],
        margemFlat: margemFlat,
        margemOferta: margemOferta,
        clusterId: clusterMap[code],
      );
    }).toList();
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

  Future<void> saveDraft({
    required String? masterListId,
    required List<MaterialPreco> materiais,
    required List<String> targets,
    required List<RegraAjuste> regras,
  }) async {
    // FIX: adicionado 'status': 'pending' — sem ele o draft não aparece
    // na tela de aprovações que filtra por .eq('status', 'pending')
    final draft = await supabase
        .from('price_drafts')
        .insert({'master_list_id': masterListId, 'status': 'pending'})
        .select()
        .single();

    final draftId = draft['id'];

    final itens = materiais
        .where((m) => m.novoPreco > 0)
        .map(
          (m) => {
            'draft_id': draftId,
            'product_id': m.codigo,
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
  }

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
