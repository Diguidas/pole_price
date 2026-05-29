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
    // Como faremos um select com .select('*, price_lists(description)'),
    // pegamos o nome da lista mãe de dentro do relacionamento
    final priceList = json['price_lists'] as Map<String, dynamic>?;
    
    return DraftAprovacao(
      id: json['id'] ?? '',
      masterListName: priceList?['description'] ?? 'Tabela Desconhecida',
      status: json['status'] ?? 'pending',
      createdAt: json['created_at'] ?? '',
    );
  }
}