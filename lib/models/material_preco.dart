enum OrigemMaterial { sap, manual }

class MaterialPreco {
  final String codigo;
  final String description;
  final double precoAtual; // PPV CX atual (KBETR, valor da caixa)
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

  // Campos SAP para dimensionamento de caixa
  final double? pesoUnidade; // peso por unidade em KG (ex: 0.36)
  final double? pesoCaixa;   // peso total da caixa em KG (ex: 20.16)
  final String? unidadeVenda; // ex: 'KG', 'UN', 'CX'

  // Campos SAP necessários para o push de volta ao SAP
  final String? konwa; // moeda (ex: BRL)
  final String? kmein; // unidade de medida (ex: KG)
  final String? krech; // regra de cálculo (ex: C)
  final double? mxwrt; // valor máximo

  // Status do preço na lista SAP: '' = normal, 'L' = bloqueado p/ liberação, 'X' = deletado
  String sapStatus;

  // Origem do material na sessão de edição
  final OrigemMaterial origemMaterial;

  // Marcação local de remoção (não persiste, apenas esconde da UI)
  bool removido;

  // ── Novo preço (caixa) — mantido para compatibilidade com saveDraft ─────
  double novoPreco;

  // ── Overrides de sessão ─────────────────────────────────────────────────
  // Quando o usuário edita um campo calculado, o valor digitado fica aqui.
  // Ao fechar sem salvar, some. Ao salvar draft, persiste junto com o draft.
  double? ppcNovoOverride;     // PPC novo digitado pelo usuário
  double? ppcOfertaOverride;   // PPC oferta digitado pelo usuário
  double? ppvUnitNovoOverride; // PPV unit novo (quando editado direto)
  double? reajusteOverride;    // % reajuste (quando editado direto)
  double? margemFlatOverride;  // margem Pole novo (quando editado direto)
  double? margemOfertaOverride;// margem Pole oferta (quando editado direto)

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
    this.pesoUnidade,
    this.pesoCaixa,
    this.unidadeVenda,
    this.konwa,
    this.kmein,
    this.krech,
    this.mxwrt,
    this.sapStatus = '',
    this.origemMaterial = OrigemMaterial.sap,
    this.removido = false,
    this.novoPreco = 0,
    this.ppcNovoOverride,
    this.ppcOfertaOverride,
    this.ppvUnitNovoOverride,
    this.reajusteOverride,
    this.margemFlatOverride,
    this.margemOfertaOverride,
    required this.bloqueado,
    required this.inativo,
  });

  factory MaterialPreco.fromJson(Map<String, dynamic> json) {
    final desc = (json['description'] as String?)?.trim().isNotEmpty == true
        ? json['description'] as String
        : (json['maktx'] as String?)?.trim().isNotEmpty == true
            ? json['maktx'] as String
            : (json['descricao'] as String?)?.trim().isNotEmpty == true
                ? json['descricao'] as String
                : (json['name'] as String?)?.trim() ?? '';

    return MaterialPreco(
      codigo: json['product_id'] ?? '',
      description: desc,
      precoAtual: (json['price'] as num).toDouble(),
      cpv: (json['cpv'] as num?)?.toDouble(),
      margemFlat: (json['margem_flat'] as num?)?.toDouble(),
      margemOferta: (json['margem_oferta'] as num?)?.toDouble(),
      clusterId: json['pricing_cluster_id'],
      datab: json['datab'],
      datbi: json['datbi'],
      kgSug: (json['kg_sug'] as num?)?.toDouble(),
      pesoUnidade: (json['peso_unidade'] as num?)?.toDouble(),
      pesoCaixa: (json['peso_caixa'] as num?)?.toDouble(),
      unidadeVenda: json['unidade_venda'],
      origemMaterial: json['origem_material'] == 'manual'
          ? OrigemMaterial.manual
          : OrigemMaterial.sap,
      bloqueado: json['bloqueado'] ?? false,
      inativo: json['inativo'] ?? false,
    );
  }

  // ── Fator de conversão caixa → unidade ──────────────────────────────────
  // Prioridade: peso_caixa / peso_unidade (dados SAP confiáveis).
  // Fallback: precoAtual / kgSug (estimativa pelo preço).
  double? get fatorConversao {
    if (pesoCaixa != null && pesoUnidade != null && pesoUnidade! > 0) {
      return pesoCaixa! / pesoUnidade!;
    }
    if (kgSug != null && kgSug! > 0 && precoAtual > 0) {
      return precoAtual / kgSug!;
    }
    return null;
  }

  /// Alias de compatibilidade (código legado usava fatorUnidade).
  double? get fatorUnidade => fatorConversao;

  // ── Seção ATUAL ──────────────────────────────────────────────────────────

  /// PPV Unitário Atual = PPV_cx_atual / fator_conversao
  double? get ppvUnitAtual {
    final fator = fatorConversao;
    if (fator == null || fator <= 0) return kgSug ?? (precoAtual > 0 ? precoAtual : null);
    return precoAtual / fator;
  }

  /// PPC Atual — hoje não existe no modelo; retorna null (será digitado).
  /// Reservado para quando vier do ppc_history.
  double? get ppcAtual => null;

  /// Margem Cliente Atual = 1 - (PPV_unit_atual / PPC_atual)
  double? get margemClienteAtual {
    final ppv = ppvUnitAtual;
    final ppc = ppcAtual;
    if (ppv == null || ppc == null || ppc <= 0) return null;
    return 1 - (ppv / ppc);
  }

  /// MC R$ Pole Atual = PPV_unit_atual - CPV - deduções - desp_var
  /// Simplificado: usa apenas CPV por ora (deduções e desp_var não estão no modelo ainda).
  double? get mcReaisAtual {
    final ppv = ppvUnitAtual;
    if (ppv == null || cpv == null) return null;
    return ppv - cpv!;
  }

  /// MC % Pole Atual = MC_R$ / PPV_unit_atual
  double? get mcPctAtual {
    final mc = mcReaisAtual;
    final ppv = ppvUnitAtual;
    if (mc == null || ppv == null || ppv <= 0) return null;
    return mc / ppv;
  }

  // ── Seção NOVO ───────────────────────────────────────────────────────────

  /// Margem flat efetiva: usa override se o usuário editou, senão usa a da política.
  double? get margemFlatEfetiva => margemFlatOverride ?? margemFlat;

  /// PPV Unitário Novo = PPC_novo × (1 - margem_flat_pole)
  /// Se o usuário editou diretamente o PPV, usa o override.
  double? get ppvUnitNovo {
    if (ppvUnitNovoOverride != null) return ppvUnitNovoOverride;
    final ppc = ppcNovoEfetivo;
    final mf = margemFlatEfetiva;
    if (ppc == null || mf == null) return null;
    return ppc * (1 - mf);
  }

  /// PPC Novo efetivo: usa override do usuário se existir.
  double? get ppcNovoEfetivo => ppcNovoOverride;

  /// PPV Caixa Novo = PPV_unit_novo × fator_conversao
  double? get ppvCxNovo {
    final ppv = ppvUnitNovo;
    final fator = fatorConversao;
    if (ppv == null || fator == null) return null;
    return ppv * fator;
  }

  /// Margem Cliente Novo = 1 - (PPV_unit_novo / PPC_novo)
  double? get margemClienteNovo {
    final ppv = ppvUnitNovo;
    final ppc = ppcNovoEfetivo;
    if (ppv == null || ppc == null || ppc <= 0) return null;
    return 1 - (ppv / ppc);
  }

  /// MC R$ Pole Novo = PPV_unit_novo - CPV
  double? get mcReaisNovo {
    final ppv = ppvUnitNovo;
    if (ppv == null || cpv == null) return null;
    return ppv - cpv!;
  }

  /// MC % Pole Novo = MC_R$_novo / PPV_unit_novo
  double? get mcPctNovo {
    final mc = mcReaisNovo;
    final ppv = ppvUnitNovo;
    if (mc == null || ppv == null || ppv <= 0) return null;
    return mc / ppv;
  }

  /// % Reajuste = (PPV_unit_novo / PPV_unit_atual) - 1
  double? get reajustePct {
    if (reajusteOverride != null) return reajusteOverride;
    final atual = ppvUnitAtual;
    final novo = ppvUnitNovo;
    if (atual == null || novo == null || atual <= 0) return null;
    return (novo / atual) - 1;
  }

  // ── Seção OFERTA ─────────────────────────────────────────────────────────

  /// Margem oferta efetiva: usa override se o usuário editou.
  double? get margemOfertaEfetiva => margemOfertaOverride ?? margemOferta;

  /// PPV Unit Oferta = PPC_oferta × (1 - margem_oferta_pole)
  double? get ppvUnitOferta {
    final ppc = ppcOfertaOverride;
    final mo = margemOfertaEfetiva;
    if (ppc == null || mo == null) return null;
    return ppc * (1 - mo);
  }

  // ── Cálculos bidirecionais ───────────────────────────────────────────────

  /// Calcula PPC Novo a partir de um PPV Unit digitado.
  /// PPC = PPV_unit / (1 - margem_flat_pole)
  double? ppcDePpvUnit(double ppvUnit) {
    final mf = margemFlatEfetiva;
    if (mf == null || mf >= 1) return null;
    return ppvUnit / (1 - mf);
  }

  /// Calcula PPV Unit Novo a partir de um % reajuste digitado.
  /// PPV_unit_novo = PPV_unit_atual × (1 + reajuste%)
  double? ppvUnitDeReajuste(double reajustePct) {
    final atual = ppvUnitAtual;
    if (atual == null) return null;
    return atual * (1 + reajustePct);
  }

  /// Calcula PPV Unit a partir de margem cliente digitada.
  /// PPV_unit = PPC × (1 - MC_cliente)
  double? ppvUnitDeMargemCliente(double mcCliente, double ppc) {
    return ppc * (1 - mcCliente);
  }

  // ── Status e semáforo ────────────────────────────────────────────────────

  /// Retorna a margem Pole % ativa para exibição e semáforo:
  ///   - se há PPC novo → usa mcPctNovo
  ///   - fallback → usa mcPctAtual
  double? get margemReal => mcPctNovo ?? mcPctAtual;

  /// Status de margem baseado na margem Pole % efetiva.
  String get statusMargem {
    final m = margemReal;
    if (m == null) return 'sem-cpv';
    if (m < 0) return 'prejuizo';
    if (m == 0) return 'sem margem';
    final mf = margemFlatEfetiva;
    final mo = margemOfertaEfetiva;
    if (mf != null && m >= mf) return 'ok';
    if (mo != null && m >= mo) return 'atencao';
    return 'critico';
  }

  /// Margem calculada sobre um preço de CAIXA (para compatibilidade com UI legada).
  double? margemParaPreco(double precoCaixa) {
    final fator = fatorConversao;
    final preco = (fator != null && fator > 0) ? precoCaixa / fator : precoCaixa;
    if (cpv == null || cpv! <= 0 || preco <= 0) return null;
    return (preco - cpv!) / preco;
  }

  String statusMargemParaPreco(double precoCaixa) {
    final m = margemParaPreco(precoCaixa);
    if (m == null) return 'sem-cpv';
    if (m < 0) return 'prejuizo';
    if (m == 0) return 'sem margem';
    final mf = margemFlatEfetiva;
    final mo = margemOfertaEfetiva;
    if (mf != null && m >= mf) return 'ok';
    if (mo != null && m >= mo) return 'atencao';
    return 'critico';
  }

  double? get margemSugerida {
    final base = (kgSug != null && kgSug! > 0)
        ? kgSug
        : (precoAtual > 0 ? precoAtual : null);
    if (base == null || cpv == null || cpv! <= 0) return null;
    return (base! - cpv!) / base!;
  }

  /// Vigência formatada como DD/MM/AAAA → DD/MM/AAAA
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
}