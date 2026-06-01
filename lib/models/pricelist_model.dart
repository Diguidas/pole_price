class PriceList {
  final String id;          // internamente 'id', vem do campo 'pltyp'
  final String description; // vem do campo 'ptext'

  PriceList({required this.id, required this.description});

  factory PriceList.fromJson(Map<String, dynamic> json) {
    return PriceList(
      id: json['pltyp'].toString(),
      description: json['ptext']?.toString() ?? json['pltyp'].toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PriceList && other.id == id);

  @override
  int get hashCode => id.hashCode;
}