/// Lista (mãe ou filha) de um rascunho, com a vigência e o status de envio ao
/// SAP próprios (tabela `price_draft_lists`).
class DraftLista {
  final String pltyp;
  final bool isMaster;
  String nome;

  /// Vigência no formato SAP AAAAMMDD (null = usa a do rascunho).
  String? datab;
  String? datbi;

  /// 'pending' (aguardando aprovação), 'sent' (enviada) ou 'error' (enviada,
  /// mas o SAP não confirmou algum material).
  String status;
  DateTime? sentAt;
  String? sentByEmail;

  /// Total de materiais do rascunho e os que NÃO vão para esta lista
  /// (códigos). A lista mãe nunca exclui nada.
  int totalMateriais = 0;
  Set<String> excluidos = <String>{};

  int get qtdEnviados => totalMateriais - excluidos.length;

  DraftLista({
    required this.pltyp,
    required this.isMaster,
    required this.nome,
    this.datab,
    this.datbi,
    this.status = 'pending',
    this.sentAt,
    this.sentByEmail,
  });

  bool get pendente => status == 'pending';
  bool get enviada => status == 'sent';
  bool get comErro => status == 'error';

  /// Já foi publicada (com ou sem erro) — não volta a 'pending'.
  bool get foiPublicada => status != 'pending';

  bool get temVigencia =>
      (datab != null && datab!.isNotEmpty) &&
      (datbi != null && datbi!.isNotEmpty);

  /// AAAAMMDD → DD/MM/AAAA ('—' se vazio).
  static String formatar(String? sap) {
    if (sap == null || sap.length < 8) return '—';
    return '${sap.substring(6, 8)}/${sap.substring(4, 6)}/${sap.substring(0, 4)}';
  }

  /// DateTime → AAAAMMDD.
  static String paraSap(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  /// AAAAMMDD → DateTime (null se inválido).
  static DateTime? deSap(String? sap) {
    if (sap == null || sap.length < 8) return null;
    final y = int.tryParse(sap.substring(0, 4));
    final m = int.tryParse(sap.substring(4, 6));
    final d = int.tryParse(sap.substring(6, 8));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
}

/// Resultado de [DraftPricingService.carregarListasDoDraft].
class DraftListasResult {
  final List<DraftLista> listas;

  /// `false` quando a tabela `price_draft_lists` ainda não existe no banco
  /// (migração pendente): as listas vêm só da leitura do rascunho e não dá
  /// para editar vigência/status por lista.
  final bool persistido;

  const DraftListasResult({required this.listas, required this.persistido});
}
