import 'package:pole_price/models/product_group_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductGroupService {
  final SupabaseClient supabase;

  ProductGroupService(this.supabase);

  /// Carrega a hierarquia completa: Categoria → Linha → Grupo → Cluster (com contagem de SKUs)
  Future<List<ProductCategory>> getHierarchy() async {
    // 1. Busca clusters
    final clustersRes = await supabase
        .from('pricing_clusters')
        .select('id, name, group_id')
        .order('name');

    // 2. Conta SKUs por cluster
    final countsRes = await supabase
        .from('products')
        .select('pricing_cluster_id');

    final Map<String, int> skuCount = {};
    for (final p in countsRes as List) {
      final cid = p['pricing_cluster_id'] as String?;
      if (cid != null) skuCount[cid] = (skuCount[cid] ?? 0) + 1;
    }

    // 3. Monta clusters agrupados por group_id
    final clusters = <String, List<PricingCluster>>{};
    for (final c in clustersRes as List) {
      final groupId = c['group_id'] as String? ?? '';
      clusters.putIfAbsent(groupId, () => []).add(
            PricingCluster(
              id: c['id'] ?? '',
              name: c['name'] ?? '',
              groupId: groupId,
              skuCount: skuCount[c['id']] ?? 0,
            ),
          );
    }

    // 4. Busca grupos
    final groupsRes = await supabase
        .from('product_groups')
        .select('id, name, line_id')
        .order('name');

    // 5. Busca linhas
    final linesRes = await supabase
        .from('product_lines')
        .select('id, name, category_id')
        .order('name');

    // 6. Busca categorias
    final catsRes = await supabase
        .from('product_categories')
        .select('id, name')
        .order('name');

    // Monta grupos agrupados por line_id
    final groups = <String, List<ProductGroup>>{};
    for (final g in groupsRes as List) {
      final lineId = g['line_id'] as String? ?? '';
      groups.putIfAbsent(lineId, () => []).add(
            ProductGroup(
              id: g['id'] ?? '',
              name: g['name'] ?? '',
              lineId: lineId,
              clusters: clusters[g['id']] ?? [],
            ),
          );
    }

    // Monta linhas agrupadas por category_id
    final lines = <String, List<ProductLine>>{};
    for (final l in linesRes as List) {
      final catId = l['category_id'] as String? ?? '';
      lines.putIfAbsent(catId, () => []).add(
            ProductLine(
              id: l['id'] ?? '',
              name: l['name'] ?? '',
              categoryId: catId,
              groups: groups[l['id']] ?? [],
            ),
          );
    }

    // Monta e retorna categorias
    return (catsRes as List).map((c) {
      return ProductCategory(
        id: c['id'] ?? '',
        name: c['name'] ?? '',
        lines: lines[c['id']] ?? [],
      );
    }).toList();
  }

  /// Busca os produtos de um cluster específico
  Future<List<ClusterProduct>> getProductsByCluster(String clusterId) async {
    final res = await supabase
        .from('products')
        .select('code, name, product_costs(cost_value, period)')
        .eq('pricing_cluster_id', clusterId)
        .order('name');

    return (res as List).map((p) {
      final costs = p['product_costs'] as List? ?? [];
      costs.sort(
        (a, b) => (b['period'] as String).compareTo(a['period'] as String),
      );

      return ClusterProduct(
        code: p['code'] ?? '',
        description: p['name'] ?? '',
        cpv: costs.isNotEmpty
            ? (costs.first['cost_value'] as num?)?.toDouble()
            : null,
      );
    }).toList();
  }
}