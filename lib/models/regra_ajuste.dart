class RegraAjuste {
  final String targetListId;
  final String nivel;
  final String tipo;
  final double valor;
  final String? clusterId;
  final String? clusterNome;  // ← novo
  final String? materialId;
  final String? materialNome; // ← novo

  RegraAjuste({
    required this.targetListId,
    required this.nivel,
    required this.tipo,
    required this.valor,
    this.clusterId,
    this.clusterNome,
    this.materialId,
    this.materialNome,
  });
}