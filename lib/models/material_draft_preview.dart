import 'package:pole_price/models/material_preco.dart';

class MaterialDraftPreview {
  final String materialRowId;
  final String productId;
  final String description;
  final String listaId;
  final String listaNome;
  final String tipoLista;
  final double precoAntigo;
  final double precoNovo;
  final String origem;
  final bool foiEditado;

  // Campos SAP necessários para o push (gravados em price_draft_items)
  final String? konwa;
  final String? kmein;
  final String? krech;
  final double? mxwrt;
  final String sapStatus;

  // Congelados no momento do draft — usados para reconstruir o card
  // completo (Atual/Novo/Oferta) na tela de histórico.
  final double? cpv;
  final double? kgSug;
  final double? ppcNovo;
  final double? ppcOferta;
  final double? margemFlatOverride;
  final double? margemOfertaOverride;

  // Não são congelados no draft — vêm do cadastro atual do material/custo.
  final double? pesoUnidade;
  final double? pesoCaixa;
  final double? dedPct;
  final double? dvPct;
  final double? margemFlat;
  final double? margemOferta;

  MaterialDraftPreview({
    required this.materialRowId,
    required this.productId,
    required this.description,
    required this.listaId,
    required this.listaNome,
    required this.tipoLista,
    required this.precoAntigo,
    required this.precoNovo,
    required this.origem,
    required this.foiEditado,
    this.konwa,
    this.kmein,
    this.krech,
    this.mxwrt,
    this.sapStatus = '',
    this.cpv,
    this.kgSug,
    this.ppcNovo,
    this.ppcOferta,
    this.margemFlatOverride,
    this.margemOfertaOverride,
    this.pesoUnidade,
    this.pesoCaixa,
    this.dedPct,
    this.dvPct,
    this.margemFlat,
    this.margemOferta,
  });

  Map<String, dynamic> toRowMap() => {
    'material_row_id': materialRowId,
    'product_id': productId,
    'description': description,
    'lista_id': listaId,
    'lista_nome': listaNome,
    'tipo_lista': tipoLista,
    'preco_antigo': precoAntigo,
    'preco_novo': precoNovo,
    'origem': origem,
    'foi_editado': foiEditado,
    if (konwa != null) 'konwa': konwa,
    if (kmein != null) 'kmein': kmein,
    if (krech != null) 'krech': krech,
    if (mxwrt != null) 'mxwrt': mxwrt,
    'sap_status': sapStatus,
  };

  /// Reconstrói um MaterialPreco a partir deste item de draft, para exibir
  /// o card completo (Atual/Novo/Oferta) na tela de histórico. CPV/PPC/
  /// margens override vêm congelados do draft; peso/Ded%/DV%/margens da
  /// política são os valores atuais (não são congelados por item de draft).
  MaterialPreco toMaterialPreco() {
    return MaterialPreco(
      codigo: productId,
      description: description,
      precoAtual: precoAntigo,
      cpv: cpv,
      dedPct: dedPct,
      dvPct: dvPct,
      margemFlat: margemFlat,
      margemOferta: margemOferta,
      kgSug: kgSug,
      pesoUnidade: pesoUnidade,
      pesoCaixa: pesoCaixa,
      konwa: konwa,
      kmein: kmein,
      krech: krech,
      mxwrt: mxwrt,
      sapStatus: sapStatus,
      novoPreco: precoNovo,
      ppcNovoOverride: ppcNovo,
      ppcOfertaOverride: ppcOferta,
      margemFlatOverride: margemFlatOverride,
      margemOfertaOverride: margemOfertaOverride,
      bloqueado: false,
      inativo: false,
    );
  }
}

class DraftPreviewResult {
  final List<MaterialDraftPreview> materiais;
  final String resumo;

  DraftPreviewResult({required this.materiais, required this.resumo});
}
