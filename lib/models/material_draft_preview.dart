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
      };
}

class DraftPreviewResult {
  final List<MaterialDraftPreview> materiais;
  final String resumo;

  DraftPreviewResult({required this.materiais, required this.resumo});
}
