class PricingClusterItem {
  final String id;
  final String name;

  PricingClusterItem({required this.id, required this.name});

  factory PricingClusterItem.fromJson(Map<String, dynamic> json) {
    return PricingClusterItem(id: json['id'] ?? '', name: json['name'] ?? '');
  }

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PricingClusterItem && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
