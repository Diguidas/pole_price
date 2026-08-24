enum OrigemMaterial { sap, manual }

class MaterialPreco {
  final String codigo;
  final String description;
  final double precoAtual; // PPV CX atual (KBETR, valor da caixa)
  final String? clusterId;

  // ── Vínculo de preço pai/filho dentro do agrupamento ────────────────────
  final String? agrupamentoPreco;
  final String? materialPaiCode; // preenchido só quando este material é filho
  final double? excecaoPrecoPct; // delta % em relação ao pai (ex: 0.10 = +10%)

  // CPV do período mais recente (por KG)
  final double? cpv;

  // Ded% e DV% do período mais recente (vêm da planilha de import, tabela product_costs)
  final double? dedPct;
  final double? dvPct;

  // Política: Margem Cliente padrão ("venda padrão") e Margem Cliente da
  // Oferta ("mínimo promocional") — ambas usadas para calcular o PPV a
  // partir do PPC (Passos 1 e 9). Não são limiares de MC Pole.
  final double? margemFlat; // = Margem Cliente padrão da política
  final double? margemOferta; // = Margem Cliente da Oferta da política

  // PPC do ciclo aprovado mais recente (tabela ppc_historico, por lista).
  // Sem histórico (produto novo/primeiro ciclo), fica null.
  final double? ppcHistorico;

  // Vigência do preço (formato SAP: YYYYMMDD) — mutável para edição por linha
  String? datab;
  String? datbi;
  final bool bloqueado;
  final bool inativo;

  // Preço sugerido por kg — vem do SAP junto com KBETR (campo KG_SUG / KBPER)
  final double? kgSug;

  // Campos SAP para dimensionamento de caixa
  final double? pesoUnidade; // peso por unidade em KG (ex: 0.36)
  final double? pesoCaixa; // peso total da caixa em KG (ex: 20.16)
  final String? unidadeVenda; // ex: 'KG', 'UN', 'CX'

  // Campos SAP necessários para o push de volta ao SAP
  final String? konwa; // moeda (ex: BRL)
  final String? kmein; // unidade de medida (ex: KG)
  final String? krech; // regra de cálculo (ex: C)

  // Limites de preço da condição no SAP (VK11, tela de detalhe). Podem vir
  // de duas fontes: (1) o botão "Limites SAP" por linha, que seta o valor em
  // R$ manualmente e trava o material (mxwrtGkwrtManual = true), ou (2) o
  // botão "Limites SAP" geral no topo, que calcula a partir de uma % por
  // agrupamento — só materiais não travados são recalculados por ele.
  // Quando não informados, vão como 0,00 puro para o SAP, sem fallback.
  double? mxwrt; // valor inferior
  double? gkwrt; // valor superior
  bool mxwrtGkwrtManual = false; // true = travado pelo dialog por linha

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
  double? ppcNovoOverride; // PPC novo digitado pelo usuário
  double? ppcOfertaOverride; // PPC oferta digitado pelo usuário
  double? ppvUnitNovoOverride; // PPV unit novo (quando editado direto)
  double? ppvUnitOfertaOverride; // PPV unit oferta (quando editado direto)
  double? reajusteOverride; // % reajuste (quando editado direto)
  double? margemFlatOverride; // margem Pole novo (quando editado direto)
  double? margemOfertaOverride; // margem Pole oferta (quando editado direto)

  bool ppvUnitNovoLimpo = false;

  MaterialPreco({
    required this.codigo,
    required this.description,
    required this.precoAtual,
    this.cpv,
    this.dedPct,
    this.dvPct,
    this.margemFlat,
    this.margemOferta,
    this.ppcHistorico,
    this.clusterId,
    this.agrupamentoPreco,
    this.materialPaiCode,
    this.excecaoPrecoPct,
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
    this.gkwrt,
    this.sapStatus = '',
    this.origemMaterial = OrigemMaterial.sap,
    this.removido = false,
    this.novoPreco = 0,
    this.ppcNovoOverride,
    this.ppcOfertaOverride,
    this.ppvUnitNovoOverride,
    this.ppvUnitOfertaOverride,
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
      dedPct: (json['ded_pct'] as num?)?.toDouble(),
      dvPct: (json['dv_pct'] as num?)?.toDouble(),
      margemFlat: (json['margem_flat'] as num?)?.toDouble(),
      margemOferta: (json['margem_oferta'] as num?)?.toDouble(),
      ppcHistorico: (json['ppc_historico'] as num?)?.toDouble(),
      clusterId: json['pricing_cluster_id'],
      agrupamentoPreco: json['agrupamento_preco']?.toString(),
      materialPaiCode: json['material_pai_code']?.toString(),
      excecaoPrecoPct: (json['excecao_preco_pct'] as num?)?.toDouble(),
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

  double _r2(double v) => (v * 100).round() / 100;

  /// PPV por KG = PPV Unitário ÷ peso da embalagem (kg). Passo 3 da especificação.
  double? _ppvPorKg(double? ppvUnit) {
    if (ppvUnit == null || pesoUnidade == null || pesoUnidade! <= 0)
      return null;
    return ppvUnit / pesoUnidade!;
  }

  /// DV R$ = DV% × PPV/KG. Passo 4.
  double? _dvReais(double? ppvKg) {
    if (ppvKg == null || dvPct == null) return null;
    return dvPct! * ppvKg;
  }

  /// Ded R$ = (PPV/KG − DV R$) × Ded%. Passo 5.
  double? _dedReais(double? ppvKg, double? dvReais) {
    if (ppvKg == null || dvReais == null || dedPct == null) return null;
    return (ppvKg - dvReais) * dedPct!;
  }

  /// MC R$ Pole = PPV/KG − CPV − Ded R$ − DV R$. Passo 6.
  double? _mcReais(double? ppvKg, double? dedReais, double? dvReais) {
    if (ppvKg == null || cpv == null || dedReais == null || dvReais == null) {
      return null;
    }
    return ppvKg - cpv! - dedReais - dvReais;
  }

  /// MC % Pole = MC R$ ÷ (PPV/KG − Ded R$). Passo 7.
  double? _mcPct(double? mcReais, double? ppvKg, double? dedReais) {
    if (mcReais == null || ppvKg == null || dedReais == null) return null;
    final base = ppvKg - dedReais;
    if (base <= 0) return null;
    return mcReais / base;
  }

  // ── Seção ATUAL ──────────────────────────────────────────────────────────

  /// PPV Unitário Atual = PPV_cx_atual / fator_conversao (vem do SAP ao vivo).
  double? get ppvUnitAtual {
    final fator = fatorConversao;
    if (fator == null || fator <= 0)
      return kgSug ?? (precoAtual > 0 ? precoAtual : null);
    return precoAtual / fator;
  }

  /// PPC Atual — vem do histórico de PPC (lista + vigência) quando existir.
  /// Sem histórico (produto novo), fica null — não é digitado manualmente.
  double? get ppcAtual => ppcHistorico;

  /// Margem Cliente Atual = 1 - (PPV_unit_atual / PPC_atual). Resultado, não input.
  double? get margemClienteAtual {
    final ppv = ppvUnitAtual;
    final ppc = ppcAtual;
    if (ppv == null || ppc == null || ppc <= 0) return null;
    return 1 - (ppv / ppc);
  }

  double? get ppvKgAtual => _ppvPorKg(ppvUnitAtual);
  double? get dvReaisAtual => _dvReais(ppvKgAtual);
  double? get dedReaisAtual => _dedReais(ppvKgAtual, dvReaisAtual);

  /// MC R$ Pole Atual — Passo 6, calculado sobre o PPV/KG.
  double? get mcReaisAtual => _mcReais(ppvKgAtual, dedReaisAtual, dvReaisAtual);

  /// MC % Pole Atual — Passo 7.
  double? get mcPctAtual => _mcPct(mcReaisAtual, ppvKgAtual, dedReaisAtual);

  // ── Seção NOVO ───────────────────────────────────────────────────────────

  /// Margem Cliente efetiva (padrão da política, ou override do usuário no draft).
  double? get margemFlatEfetiva => margemFlatOverride ?? margemFlat;

  /// PPV Unitário Novo = PPC_novo × (1 - Margem Cliente). Passo 1.
  /// Se o usuário editou diretamente o PPV, usa o override.
  double? get ppvUnitNovo {
    if (ppvUnitNovoLimpo) return null; // limpeza explícita vence a fórmula
    if (ppvUnitNovoOverride != null) return ppvUnitNovoOverride;
    final ppc = ppcNovoEfetivo;
    final mf = margemFlatEfetiva;
    if (ppc == null || mf == null) return null;
    return ppc * (1 - mf);
  }

  /// PPC Novo — sempre input manual (benchmarking de mercado).
  double? get ppcNovoEfetivo => ppcNovoOverride;

  /// PPV Caixa Novo = PPV_unit_novo × fator_conversao. Passo 2.
  double? get ppvCxNovo {
    final ppv = ppvUnitNovo;
    final fator = fatorConversao;
    if (ppv == null || fator == null) return null;
    return ppv * fator;
  }

  /// Margem Cliente Novo = 1 - (PPV_unit_novo / PPC_novo). Sempre a partir
  /// do PPC/Margem Cliente deste cenário — nunca derivada do cenário Atual.
  double? get margemClienteNovo {
    final ppv = ppvUnitNovo;
    final ppc = ppcNovoEfetivo;
    if (ppv == null || ppc == null || ppc <= 0) return null;
    return 1 - (ppv / ppc);
  }

  double? get ppvKgNovo => _ppvPorKg(ppvUnitNovo);
  double? get dvReaisNovo => _dvReais(ppvKgNovo);
  double? get dedReaisNovo => _dedReais(ppvKgNovo, dvReaisNovo);

  /// MC R$ Pole Novo — Passo 6, calculado sobre o PPV/KG. Nunca é input.
  double? get mcReaisNovo => _mcReais(ppvKgNovo, dedReaisNovo, dvReaisNovo);

  /// MC % Pole Novo — Passo 7.
  double? get mcPctNovo => _mcPct(mcReaisNovo, ppvKgNovo, dedReaisNovo);

  /// % Reajuste = (PPV_unit_novo / PPV_unit_atual) - 1. Passo 8.
  double? get reajustePct {
    if (reajusteOverride != null) return reajusteOverride;
    final atual = ppvUnitAtual;
    final novo = ppvUnitNovo;
    if (atual == null || novo == null || atual <= 0) return null;
    return (novo / atual) - 1;
  }

  // ── Seção OFERTA ─────────────────────────────────────────────────────────

  /// Margem Cliente da Oferta ("mínimo promocional" da política) — mesma
  /// natureza de margemFlat, só que o valor usado no cenário promocional.
  double? get margemOfertaEfetiva => margemOfertaOverride ?? margemOferta;

  /// PPV Unit Oferta = ROUND(PPC × (1 − Margem Cliente Oferta), 2). Passo 9.
  /// Mesma fórmula do PPV Novo, só troca a margem cliente usada.
  /// Usa o PPC digitado no cenário Oferta ou, se ausente, o mesmo PPC do Novo.
  /// Se o usuário editou o PPV Unit Oferta diretamente, usa o override.
  double? get ppvUnitOferta {
    if (ppvUnitOfertaOverride != null) return ppvUnitOfertaOverride;
    final ppc = ppcOfertaOverride ?? ppcNovoEfetivo;
    final margem = margemOfertaEfetiva;
    if (ppc == null || margem == null) return null;
    return _r2(ppc * (1 - margem));
  }

  /// Calcula PPC Oferta a partir de um PPV Unit Oferta digitado.
  /// PPC = PPV_unit / (1 - margem_oferta_pole)
  double? ppcOfertaDePpvUnit(double ppvUnit) {
    final margem = margemOfertaEfetiva;
    if (margem == null || margem >= 1) return null;
    return ppvUnit / (1 - margem);
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

  /// Status de margem baseado na MC% Pole efetiva, comparada contra a
  /// Margem Cliente e Margem Oferta da política não são limiares de MC Pole
  /// (contribuição) — são a margem usada para calcular o preço a partir do
  /// PPC. Sem uma margem mínima de MC Pole definida na política ainda, o
  /// semáforo só distingue prejuízo (MC Pole negativa) de ok.
  String get statusMargem {
    final m = margemReal;
    if (m == null) return 'sem-cpv';
    if (m < 0) return 'prejuizo';
    if (m == 0) return 'sem margem';
    return 'ok';
  }

  /// Margem calculada sobre um preço de CAIXA (para compatibilidade com UI legada).
  double? margemParaPreco(double precoCaixa) {
    final fator = fatorConversao;
    final preco = (fator != null && fator > 0)
        ? precoCaixa / fator
        : precoCaixa;
    if (cpv == null || cpv! <= 0 || preco <= 0) return null;
    return (preco - cpv!) / preco;
  }

  String statusMargemParaPreco(double precoCaixa) {
    final m = margemParaPreco(precoCaixa);
    if (m == null) return 'sem-cpv';
    if (m < 0) return 'prejuizo';
    if (m == 0) return 'sem margem';
    return 'ok';
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
