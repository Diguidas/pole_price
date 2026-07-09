// lib/models/material_model.dart

class MaterialSap {
  // ── Campos SAP (readonly) ─────────────────────────────────
  final String materialCode; // MATNR limpo (sem zeros à esquerda)
  final String description;  // NOME do SAP
  final String? unidadeVenda;
  final double? pesoUnidade;
  final String? unidadePeso;
  final double? pesoCaixa;
  final double? fatorConversao; // gerado: peso_caixa / peso_unidade

  // ── Agrupadores (editáveis via planilha) ─────────────────
  final String? empresa;
  final String? marca;
  final String? gramatura;
  final String? categoria;
  final String? linha;
  final String? agrupamentoPreco;

  // ── Vínculo de preço pai/filho dentro do agrupamento ─────
  final String? materialPaiCode; // preenchido só quando este material é filho
  final double? excecaoPrecoPct; // delta % em relação ao pai (ex: 0.10 = +10%)

  // ── Custos (editáveis via planilha) ──────────────────────
  final double? cpvReais;
  final double? cpvPct;
  final double? deducoesPct;
  final double? deducoesReais;
  final double? despesasVarPct;
  final double? despesasVarReais;

  // ── Metadata ─────────────────────────────────────────────
  final DateTime? updatedAt;

  const MaterialSap({
    required this.materialCode,
    required this.description,
    this.unidadeVenda,
    this.pesoUnidade,
    this.unidadePeso,
    this.pesoCaixa,
    this.fatorConversao,
    this.empresa,
    this.marca,
    this.gramatura,
    this.categoria,
    this.linha,
    this.agrupamentoPreco,
    this.materialPaiCode,
    this.excecaoPrecoPct,
    this.cpvReais,
    this.cpvPct,
    this.deducoesPct,
    this.deducoesReais,
    this.despesasVarPct,
    this.despesasVarReais,
    this.updatedAt,
  });

  factory MaterialSap.fromJson(Map<String, dynamic> json) {
    return MaterialSap(
      materialCode: json['material_code']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      unidadeVenda: json['unidade_venda']?.toString(),
      pesoUnidade: _toDouble(json['peso_unidade']),
      unidadePeso: json['unidade_peso']?.toString(),
      pesoCaixa: _toDouble(json['peso_caixa']),
      fatorConversao: _toDouble(json['fator_conversao']),
      empresa: json['empresa']?.toString(),
      marca: json['marca']?.toString(),
      gramatura: json['gramatura']?.toString(),
      categoria: json['categoria']?.toString(),
      linha: json['linha']?.toString(),
      agrupamentoPreco: json['agrupamento_preco']?.toString(),
      materialPaiCode: json['material_pai_code']?.toString(),
      excecaoPrecoPct: _toDouble(json['excecao_preco_pct']),
      cpvReais: _toDouble(json['cpv_reais']),
      cpvPct: _toDouble(json['cpv_pct']),
      deducoesPct: _toDouble(json['deducoes_pct']),
      deducoesReais: _toDouble(json['deducoes_reais']),
      despesasVarPct: _toDouble(json['despesas_var_pct']),
      despesasVarReais: _toDouble(json['despesas_var_reais']),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    return double.tryParse(v.toString());
  }

  /// True se tem todos os agrupadores preenchidos
  bool get hierarquiaCompleta =>
      empresa != null &&
      marca != null &&
      gramatura != null &&
      categoria != null &&
      linha != null &&
      agrupamentoPreco != null;

  /// True se tem CPV definido
  bool get temCpv => cpvReais != null && cpvReais! > 0;

  /// Status de completude para badge visual
  MaterialStatus get status {
    if (!hierarquiaCompleta) return MaterialStatus.semHierarquia;
    if (!temCpv) return MaterialStatus.semCpv;
    return MaterialStatus.completo;
  }
}

enum MaterialStatus { completo, semCpv, semHierarquia }