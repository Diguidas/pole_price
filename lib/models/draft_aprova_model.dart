class DraftAprovacao {
  final String id;
  final String masterListName;
  final String status;
  final String createdAt;

  DraftAprovacao({
    required this.id,
    required this.masterListName,
    required this.status,
    required this.createdAt,
  });

  factory DraftAprovacao.fromJson(Map<String, dynamic> json) {
    final priceList = json['price_lists'] as Map<String, dynamic>?;

    return DraftAprovacao(
      id: json['id']?.toString() ?? '',
      masterListName:
          priceList?['description']?.toString() ?? 'Tabela Desconhecida',
      status: json['status']?.toString() ?? 'pending',
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}