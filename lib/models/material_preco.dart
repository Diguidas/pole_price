class MaterialPreco {
  final String codigo;
  final String description;
  final double precoAtual;
  final String? clusterId;

  // CPV do período mais recente
  final double? cpv;

  // Margens mínimas da política da lista
  final double? margemFlat;
  final double? margemOferta;

  double novoPreco;

  MaterialPreco({
    required this.codigo,
    required this.description,
    required this.precoAtual,
    this.cpv,
    this.margemFlat,
    this.margemOferta,
    this.novoPreco = 0, this.clusterId,
  });

  factory MaterialPreco.fromJson(Map<String, dynamic> json) {
    return MaterialPreco(
      codigo: json['product_id'] ?? '',
      description: json['description'] ?? '',
      precoAtual: (json['price'] as num).toDouble(),
      cpv: (json['cpv'] as num?)?.toDouble(),
      margemFlat: (json['margem_flat'] as num?)?.toDouble(),
      margemOferta: (json['margem_oferta'] as num?)?.toDouble(),
      clusterId: json['pricing_cluster_id'],
    );
  }

  /// Margem real calculada com o preço que o usuário está digitando.
  /// Usa novoPreco se preenchido, senão precoAtual.
  double? get margemReal {
    final preco = novoPreco > 0 ? novoPreco : precoAtual;
    if (cpv == null || cpv! <= 0 || preco <= 0) return null;
    return (preco - cpv!) / preco;
  }

  /// 'ok' | 'atencao' | 'sem margem' | 'sem-cpv'
  String get statusMargem {
    final m = margemReal;
    if (m == null) return 'sem-cpv';
    if (margemFlat != null && m >= margemFlat!) return 'ok';
    if (margemOferta != null && m >= margemOferta!) return 'atencao';
    return 'sem margem';
  }
}