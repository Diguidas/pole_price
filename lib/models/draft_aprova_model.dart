class DraftAprovacao {
  final String id;
  final String masterListName;
  final String status;
  final String createdAt;
  final String? createdByEmail;
  final String? reviewedByEmail;
  final String? reviewedAt;
  final String? justificativa;

  /// Quantidade de materiais deste draft que o SAP não confirmou (ver
  /// coluna price_draft_items.sap_erro). Preenchido pela tela de Aprovações
  /// ao cruzar com os itens do draft — não vem direto da tabela price_drafts.
  final List<Map<String, dynamic>> falhas;

  DraftAprovacao({
    required this.id,
    required this.masterListName,
    required this.status,
    required this.createdAt,
    this.createdByEmail,
    this.reviewedByEmail,
    this.reviewedAt,
    this.justificativa,
    this.falhas = const [],
  });

  bool get temFalhas => falhas.isNotEmpty;

  factory DraftAprovacao.fromJson(
    Map<String, dynamic> json, {
    List<Map<String, dynamic>> falhas = const [],
  }) {
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
      justificativa: json['justificativa']?.toString(),
      falhas: falhas,
    );
  }
}