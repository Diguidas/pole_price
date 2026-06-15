class PricingPolicy {
  final String id;
  final String name;
  final double? margemFlat;
  final double? margemOferta;
  final String? descricao;
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

  String get margemOfertaFormatada =>
      margemOferta != null ? '${(margemOferta! * 100).toStringAsFixed(0)}%' : '—';
}

class PolicyPriceList {
  final String pltyp;
  final String ptext;
  final String? regraExclusiva;

  // Exceção de margem: delta em relação à política mãe
  final double? excecaoFlatPct;    // ex: +0.04 = +4%, -0.02 = -2%
  final double? excecaoOfertaPct;

  // Espelho: esta lista é filha de outra
  final String? mirrorOfPltyp;     // pltyp da lista mãe
  final List<String> mirrorFilhas; // pltyps das listas que espelham esta

  PolicyPriceList({
    required this.pltyp,
    required this.ptext,
    this.regraExclusiva,
    this.excecaoFlatPct,
    this.excecaoOfertaPct,
    this.mirrorOfPltyp,
    this.mirrorFilhas = const [],
  });

  String get id => pltyp;
  String get description => ptext;

  bool get temExcecao => excecaoFlatPct != null || excecaoOfertaPct != null;
  bool get ehEspelho => mirrorOfPltyp != null;
  bool get temEspelhos => mirrorFilhas.isNotEmpty;

  factory PolicyPriceList.fromJson(Map<String, dynamic> json) {
    return PolicyPriceList(
      pltyp: json['pltyp']?.toString() ?? '',
      ptext: json['ptext'] ?? '',
      regraExclusiva: json['regra_exclusiva'],
      excecaoFlatPct: (json['excecao_flat_pct'] as num?)?.toDouble(),
      excecaoOfertaPct: (json['excecao_oferta_pct'] as num?)?.toDouble(),
      mirrorOfPltyp: json['mirror_of_pltyp']?.toString(),
      mirrorFilhas: (json['mirror_filhas'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class AllPriceList {
  final String pltyp;
  final String ptext;
  final String? policyId;
  final double? excecaoFlatPct;
  final double? excecaoOfertaPct;
  final String? mirrorOfPltyp;

  AllPriceList({
    required this.pltyp,
    required this.ptext,
    this.policyId,
    this.excecaoFlatPct,
    this.excecaoOfertaPct,
    this.mirrorOfPltyp,
  });

  String get id => pltyp;
  String get description => ptext;
  bool get vinculada => policyId != null;
  bool get ehEspelho => mirrorOfPltyp != null;

  factory AllPriceList.fromJson(Map<String, dynamic> json) {
    return AllPriceList(
      pltyp: json['pltyp']?.toString() ?? '',
      ptext: json['ptext'] ?? '',
      policyId: json['policy_id'],
      excecaoFlatPct: (json['excecao_flat_pct'] as num?)?.toDouble(),
      excecaoOfertaPct: (json['excecao_oferta_pct'] as num?)?.toDouble(),
      mirrorOfPltyp: json['mirror_of_pltyp']?.toString(),
    );
  }
}