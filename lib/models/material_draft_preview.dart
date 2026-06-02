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
}

class DraftPreviewResult {
  final List<MaterialDraftPreview> materiais;
  final String resumo;

  DraftPreviewResult({required this.materiais, required this.resumo});
}