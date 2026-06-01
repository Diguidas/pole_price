class DraftAprovacao {
  final String id;
  final String masterListName;
  final String status;
  final String createdAt;
  final String? createdByEmail;
  final String? reviewedByEmail;
  final String? reviewedAt;

  DraftAprovacao({
    required this.id,
    required this.masterListName,
    required this.status,
    required this.createdAt,
    this.createdByEmail,
    this.reviewedByEmail,
    this.reviewedAt,
  });

  factory DraftAprovacao.fromJson(Map<String, dynamic> json) {
    return DraftAprovacao(
      id: json['id']?.toString() ?? '',
      masterListName:
          json['lista_nome']?.toString() ??
          json['master_list_id']?.toString() ??
          'Tabela Desconhecida',
      status: json['status']?.toString() ?? 'pending',
      createdAt: json['created_at']?.toString() ?? '',
      createdByEmail: json['created_by_email']?.toString(),
      reviewedByEmail: json['reviewed_by_email']?.toString(),
      reviewedAt: json['reviewed_at']?.toString(),
    );
  }
}
