class ProductCategory {
  final String id;
  final String name;
  final List<ProductLine> lines;

  ProductCategory({
    required this.id,
    required this.name,
    this.lines = const [],
  });

  int get totalSkus => lines.fold(0, (sum, l) => sum + l.totalSkus);
}

class ProductLine {
  final String id;
  final String name;
  final String categoryId;
  final List<ProductGroup> groups;

  ProductLine({
    required this.id,
    required this.name,
    required this.categoryId,
    this.groups = const [],
  });

  int get totalSkus => groups.fold(0, (sum, g) => sum + g.totalSkus);
}

class ProductGroup {
  final String id;
  final String name;
  final String lineId;
  final List<PricingCluster> clusters;

  ProductGroup({
    required this.id,
    required this.name,
    required this.lineId,
    this.clusters = const [],
  });

  int get totalSkus => clusters.fold(0, (sum, c) => sum + c.skuCount);
}

class PricingCluster {
  final String id;
  final String name;
  final String groupId;
  final int skuCount;

  PricingCluster({
    required this.id,
    required this.name,
    required this.groupId,
    required this.skuCount,
  });
}

class ClusterProduct {
  final String code;
  final String description;
  final double? cpv;

  ClusterProduct({
    required this.code,
    required this.description,
    this.cpv,
  });

  factory ClusterProduct.fromJson(Map<String, dynamic> json) {
    return ClusterProduct(
      code: json['id'] ?? '',
      description: json['description'] ?? '',
      cpv: (json['product_costs'] as List?)
              ?.firstOrNull
              .let((c) => (c['cpv'] as num?)?.toDouble()),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}