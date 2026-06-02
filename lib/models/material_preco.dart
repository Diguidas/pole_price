enum OrigemMaterial { sap, manual }

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

  // Vigência do preço (formato SAP: YYYYMMDD) — mutável para edição por linha
  String? datab;
  String? datbi;
  final bool bloqueado;
  final bool inativo;

  // Preço sugerido por kg — vem do SAP junto com KBETR (campo KG_SUG / KBPER)
  final double? kgSug;

  // Campos SAP necessários para o push de volta ao SAP
  final String? konwa; // moeda (ex: BRL)
  final String? kmein; // unidade de medida (ex: KG)
  final String? krech; // regra de cálculo (ex: C)
  final double? mxwrt; // valor máximo

  // Status do preço na lista SAP: '' = normal, 'L' = bloqueado p/ liberação, 'X' = deletado
  // Definido pelo usuário na tela de criação antes de salvar o draft.
  String sapStatus;

  // Origem do material na sessão de edição
  final OrigemMaterial origemMaterial;

  // Marcação local de remoção (não persiste, apenas esconde da UI)
  bool removido;

  double novoPreco;

  MaterialPreco({
    required this.codigo,
    required this.description,
    required this.precoAtual,
    this.cpv,
    this.margemFlat,
    this.margemOferta,
    this.clusterId,
    this.datab,
    this.datbi,
    this.kgSug,
    this.konwa,
    this.kmein,
    this.krech,
    this.mxwrt,
    this.sapStatus = '',
    this.origemMaterial = OrigemMaterial.sap,
    this.removido = false,
    this.novoPreco = 0,
    required this.bloqueado,
    required this.inativo,
  });

  factory MaterialPreco.fromJson(Map<String, dynamic> json) {
    print('DEBUG vigência: datab=${json['datab']} datbi=${json['datbi']}');
    return MaterialPreco(
      codigo: json['product_id'] ?? '',
      description: json['description'] ?? '',
      precoAtual: (json['price'] as num).toDouble(),
      cpv: (json['cpv'] as num?)?.toDouble(),
      margemFlat: (json['margem_flat'] as num?)?.toDouble(),
      margemOferta: (json['margem_oferta'] as num?)?.toDouble(),
      clusterId: json['pricing_cluster_id'],
      datab: json['datab'],
      datbi: json['datbi'],
      kgSug: (json['kg_sug'] as num?)?.toDouble(),
      origemMaterial: json['origem_material'] == 'manual'
          ? OrigemMaterial.manual
          : OrigemMaterial.sap,
      bloqueado: json['bloqueado'] ?? false,
      inativo: json['inativo'] ?? false,
    );
  }

  /// Margem real calculada com o preço que o usuário está digitando.
  /// Usa novoPreco se preenchido, senão precoAtual.
  double? get margemReal {
    final preco = novoPreco > 0 ? novoPreco : precoAtual;
    if (cpv == null || cpv! <= 0 || preco <= 0) return null;
    return (preco - cpv!) / preco;
  }

  /// Margem calculada sobre o kg_sug (preço sugerido por kg do SAP)
  double? get margemSugerida {
    final base = (kgSug != null && kgSug! > 0)
        ? kgSug
        : (precoAtual > 0 ? precoAtual : null);
    if (base == null || cpv == null || cpv! <= 0) return null;
    return (base - cpv!) / base;
  }

  /// Vigência formatada como DD/MM/AAAA — DD/MM/AAAA (ou aberta se datbi = 99991231)
  String get vigenciaFormatada {
    String fmt(String? s) {
      if (s == null || s.length < 8) return '?';
      if (s == '99991231') return 'aberta';
      return '${s.substring(6, 8)}/${s.substring(4, 6)}/${s.substring(0, 4)}';
    }

    final ini = fmt(datab);
    final fim = fmt(datbi);
    if (ini == '?' && fim == '?') return '—';
    return '$ini → $fim';
  }

  /// 'ok' | 'atencao' | 'sem margem' | 'sem-cpv'
  String get statusMargem {
    final m = margemSugerida ?? margemReal;
    if (m == null) return 'sem-cpv';
    if (margemFlat != null && m >= margemFlat!) return 'ok';
    if (margemOferta != null && m >= margemOferta!) return 'atencao';
    return 'sem margem';
  }
}
