class PriceList {
  final String id;
  final String description;

  PriceList({required this.id, required this.description});

  factory PriceList.fromJson(Map<String, dynamic> json) {
    return PriceList(id: json['id'], description: json['description']);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PriceList && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
