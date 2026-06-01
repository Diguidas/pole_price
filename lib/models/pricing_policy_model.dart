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
  final String pltyp;       // PK da tabela price_lists (antes: id)
  final String ptext;       // descrição da lista       (antes: description)
  final String? regraExclusiva;

  PolicyPriceList({
    required this.pltyp,
    required this.ptext,
    this.regraExclusiva,
  });

  // Mantém getters com os nomes antigos para não quebrar a UI
  String get id => pltyp;
  String get description => ptext;

  factory PolicyPriceList.fromJson(Map<String, dynamic> json) {
    return PolicyPriceList(
      pltyp: json['pltyp']?.toString() ?? '',
      ptext: json['ptext'] ?? '',
      regraExclusiva: json['regra_exclusiva'],
    );
  }
}

class AllPriceList {
  final String pltyp;       // PK da tabela price_lists (antes: id)
  final String ptext;       // descrição da lista       (antes: description)
  final String? policyId;

  AllPriceList({
    required this.pltyp,
    required this.ptext,
    this.policyId,
  });

  // Mantém getters com os nomes antigos para não quebrar a UI
  String get id => pltyp;
  String get description => ptext;

  factory AllPriceList.fromJson(Map<String, dynamic> json) {
    return AllPriceList(
      pltyp: json['pltyp']?.toString() ?? '',
      ptext: json['ptext'] ?? '',
      policyId: json['policy_id'],
    );
  }

  bool get vinculada => policyId != null;
}