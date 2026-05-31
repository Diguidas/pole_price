class PricingPolicy {
  final String id;
  final String name;
  final double? margemFlat;
  final double? margemOferta;
  final String? descricao;

  // listas vinculadas a esta política (carregadas junto)
  final List<PolicyPriceList> listas;

  PricingPolicy({
    required this.id,
    required this.name,
    this.margemFlat,
    this.margemOferta,
    this.descricao,
    this.listas = const [],
  });

  factory PricingPolicy.fromJson(Map<String, dynamic> json) {
    final listasJson = json['price_lists'] as List? ?? [];
    return PricingPolicy(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      margemFlat: (json['margem_flat'] as num?)?.toDouble(),
      margemOferta: (json['margem_oferta'] as num?)?.toDouble(),
      descricao: json['descricao'],
      listas: listasJson.map((l) => PolicyPriceList.fromJson(l)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'margem_flat': margemFlat,
    'margem_oferta': margemOferta,
    'descricao': descricao,
  };

  String get margemFlatFormatada =>
      margemFlat != null ? '${(margemFlat! * 100).toStringAsFixed(0)}%' : '—';

  String get margemOfertaFormatada => margemOferta != null
      ? '${(margemOferta! * 100).toStringAsFixed(0)}%'
      : '—';
}

class PolicyPriceList {
  final String id;
  final String description;
  final String? regraExclusiva;

  PolicyPriceList({
    required this.id,
    required this.description,
    this.regraExclusiva,
  });

  factory PolicyPriceList.fromJson(Map<String, dynamic> json) {
    return PolicyPriceList(
      id: json['id'] ?? '',
      description: json['description'] ?? '',
      regraExclusiva: json['regra_exclusiva'],
    );
  }
}

class AllPriceList {
  final String id;
  final String description;
  final String? policyId;

  AllPriceList({required this.id, required this.description, this.policyId});

  factory AllPriceList.fromJson(Map<String, dynamic> json) {
    return AllPriceList(
      id: json['id'] ?? '',
      description: json['description'] ?? '',
      policyId: json['policy_id'],
    );
  }

  bool get vinculada => policyId != null;
}
