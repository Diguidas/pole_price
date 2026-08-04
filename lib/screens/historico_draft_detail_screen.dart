// historico_draft_detail_screen.dart
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/material.dart';
import 'package:pole_price/models/material_draft_preview.dart';
import 'package:pole_price/models/material_preco.dart';
import 'package:pole_price/service/draft_pricing_service.dart';
import 'package:pole_price/widgets/preco/material_preco_card_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoricoDraftDetailScreen extends StatefulWidget {
  final String draftId;
  final String nomeLista;
  final String status;
  final String? createdByEmail;
  final String? reviewedByEmail;
  final String createdAt;
  final String reviewedAt;
  final String? justificativa;
  final String? vigenciaDatab; // formato SAP: YYYYMMDD
  final String? vigenciaDatbi;

  const HistoricoDraftDetailScreen({
    super.key,
    required this.draftId,
    required this.nomeLista,
    required this.status,
    this.createdByEmail,
    this.reviewedByEmail,
    required this.createdAt,
    required this.reviewedAt,
    this.justificativa,
    this.vigenciaDatab,
    this.vigenciaDatbi,
  });

  @override
  State<HistoricoDraftDetailScreen> createState() =>
      _HistoricoDraftDetailScreenState();
}

class _HistoricoDraftDetailScreenState
    extends State<HistoricoDraftDetailScreen> {
  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate400 = Color(0xFF94A3B8);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _slate100 = Color(0xFFF1F5F9);
  static const _bgSuave = Color(0xFFF8FAFC);

  late final DraftPricingService _draftService;
  bool _loading = true;
  String _erro = '';

  List<Map<String, dynamic>> _materiais = [];
  Map<String, MaterialDraftPreview> _previewByKey = {};
  String _resumo = '';
  String _filtroTab = 'todos';
  String _busca = '';
  final Set<String> _listasExpandidas = {};
  // Cache de agrupar+ordenar por lista — só depende de _materiais, não de
  // _listasExpandidas/_filtroTab/_busca. Sem isso, cada clique de
  // expandir/recolher reagrupava e reordenava tudo de novo.
  List<MapEntry<String, List<Map<String, dynamic>>>>? _gruposCache;

  @override
  void initState() {
    super.initState();
    _draftService = DraftPricingService(Supabase.instance.client);
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = '';
    });
    try {
      final preview = await _draftService.buildPreview(widget.draftId);
      setState(() {
        _materiais = preview.materiais.map((m) => m.toRowMap()).toList();
        _previewByKey = {
          for (final m in preview.materiais) '${m.productId}|${m.listaId}': m,
        };
        _resumo = preview.resumo;
        _gruposCache = null;
        // Só a lista mãe abre expandida por padrão — expandir todas de
        // uma vez com listas grandes deixava o carregamento e os toggles
        // muito lentos (a tabela não é virtualizada).
        for (final m in preview.materiais) {
          if (m.tipoLista == 'mae') {
            _listasExpandidas.add(m.listaId);
            break;
          }
        }
      });
    } catch (e) {
      setState(() => _erro = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  (String label, Color bg, Color fg) get _statusConfig =>
      switch (widget.status) {
        'approved' => (
          'Aprovado',
          const Color(0xFFECFDF5),
          const Color(0xFF047857),
        ),
        'rejected' => (
          'Rejeitado',
          const Color(0xFFFFF1F2),
          const Color(0xFFB91C1C),
        ),
        _ => ('Pendente', const Color(0xFFFFF7ED), const Color(0xFFC2410C)),
      };

  Map<String, List<Map<String, dynamic>>> _agruparPorLista() {
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final mat in _materiais) {
      grupos.putIfAbsent(mat['lista_id'] as String, () => []).add(mat);
    }
    return grupos;
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _gruposOrdenados() {
    return _gruposCache ??= _agruparPorLista().entries.toList()..sort((a, b) {
      final aMae = a.value.first['tipo_lista'] == 'mae';
      final bMae = b.value.first['tipo_lista'] == 'mae';
      if (aMae && !bMae) return -1;
      if (!aMae && bMae) return 1;
      return a.value.first['lista_nome'].toString().compareTo(
        b.value.first['lista_nome'].toString(),
      );
    });
  }

  List<Map<String, dynamic>> _filtrar(List<Map<String, dynamic>> grupo) {
    return grupo.where((item) {
      final status = _statusLabelItem(item);
      final matchTab = switch (_filtroTab) {
        'alterados' => item['foi_editado'] == true,
        'sem_alteracao' => item['foi_editado'] != true,
        'excecoes' => status == 'Exceção manual',
        _ => true,
      };
      if (!matchTab) return false;
      if (_busca.isEmpty) return true;
      final q = _busca.toLowerCase();
      return item['product_id'].toString().contains(q) ||
          item['description'].toString().toLowerCase().contains(q) ||
          item['lista_nome'].toString().toLowerCase().contains(q);
    }).toList();
  }

  static String _statusLabelItem(Map<String, dynamic> item) {
    if (item['foi_editado'] != true) return 'Sem alteração';
    final origem = item['origem']?.toString() ?? '';
    if (origem.startsWith('Reajuste')) return 'Exceção manual';
    return 'Alterado';
  }

  // ── Exportar para Excel ──────────────────────────────────────────────────
  // Exporta o que está sendo exibido na tela (respeita filtro de aba e busca),
  // com o resumo + o detalhe completo do motor de preço (Atual/Novo/Oferta)
  // de cada material, igual ao card que abre ao clicar numa linha.

  void _exportarExcel() {
    final itens = _filtrar(_materiais);
    if (itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada para exportar com o filtro atual.')),
      );
      return;
    }

    final excel = Excel.createExcel();
    final nomeAba = excel.getDefaultSheet()!;
    final sheet = excel[nomeAba];

    String fmtNum(double? v) => v != null ? v.toStringAsFixed(2) : '';
    String pct(double? v) => v != null ? (v * 100).toStringAsFixed(2) : '';

    final header = [
      'Código', 'Material', 'Lista', 'Tipo Lista',
      'Preço Anterior', 'Preço Novo', 'Dif. R\$', 'Dif. %', 'Resultado',
      // Atual
      'Atual PPV CX', 'Atual PPV Unit', 'Atual PPC',
      'Atual MC% Cliente', 'Atual MC R\$', 'Atual MC% Pole',
      // Novo
      'Novo PPV CX', 'Novo PPV Unit', 'Novo PPC',
      'Novo MC% Cliente', 'Novo MC R\$', 'Novo MC% Pole', 'Novo % Reajuste',
      // Oferta
      'Oferta % Reajuste', 'Oferta PPV Unit', 'Oferta PPC',
    ];
    sheet.appendRow(header.map((h) => TextCellValue(h)).toList());

    for (final item in itens) {
      final antigo = (item['preco_antigo'] as num).toDouble();
      final novo = (item['preco_novo'] as num).toDouble();
      final dif = novo - antigo;
      final pctDif = antigo > 0 ? (dif / antigo) * 100 : 0.0;
      final chave = '${item['product_id']}|${item['lista_id']}';
      final MaterialPreco? m = _previewByKey[chave]?.toMaterialPreco();

      final reajOferta = (m?.ppvUnitOferta != null &&
              m?.ppvUnitAtual != null &&
              m!.ppvUnitAtual! > 0)
          ? (m.ppvUnitOferta! / m.ppvUnitAtual!) - 1
          : null;

      sheet.appendRow([
        TextCellValue(item['product_id'].toString()),
        TextCellValue(item['description'].toString()),
        TextCellValue(item['lista_nome'].toString()),
        TextCellValue(
          item['tipo_lista'] == 'mae' ? 'Lista Mãe' : 'Lista Filha',
        ),
        TextCellValue(fmtNum(antigo)),
        TextCellValue(fmtNum(novo)),
        TextCellValue(fmtNum(dif)),
        TextCellValue(pctDif.toStringAsFixed(2)),
        TextCellValue(_statusLabelItem(item)),
        TextCellValue(fmtNum(m?.precoAtual)),
        TextCellValue(fmtNum(m?.ppvUnitAtual)),
        TextCellValue(fmtNum(m?.ppcAtual)),
        TextCellValue(pct(m?.margemClienteAtual)),
        TextCellValue(fmtNum(m?.mcReaisAtual)),
        TextCellValue(pct(m?.mcPctAtual)),
        TextCellValue(fmtNum(m?.ppvCxNovo)),
        TextCellValue(fmtNum(m?.ppvUnitNovo)),
        TextCellValue(fmtNum(m?.ppcNovoEfetivo)),
        TextCellValue(pct(m?.margemClienteNovo)),
        TextCellValue(fmtNum(m?.mcReaisNovo)),
        TextCellValue(pct(m?.mcPctNovo)),
        TextCellValue(pct(m?.reajustePct)),
        TextCellValue(pct(reajOferta)),
        TextCellValue(fmtNum(m?.ppvUnitOferta)),
        TextCellValue(fmtNum(m?.ppcOfertaOverride)),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) return;

    final blob = html.Blob(
      [Uint8List.fromList(bytes)],
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    final slug = widget.nomeLista.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    html.AnchorElement(href: url)
      ..setAttribute('download', 'historico_$slug.xlsx')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  _KpisSummary _kpis() {
    final total = _materiais.length;
    final alterados = _materialsFiltradosTotal();
    final excecoes = _materiais
        .where((m) => _statusLabelItem(m) == 'Exceção manual')
        .length;
    final listas = _agruparPorLista().values
        .where((g) => g.first['tipo_lista'] == 'filha')
        .length;
    return _KpisSummary(
      total: total,
      alterados: alterados,
      semAlteracao: total - alterados,
      excecoes: excecoes,
      listasFilhas: listas,
    );
  }

  int _materialsFiltradosTotal() =>
      _materiais.where((m) => m['foi_editado'] == true).length;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusBg, statusFg) = _statusConfig;

    return Scaffold(
      backgroundColor: _bgSuave,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Topbar Premium com Breadcrumb integrado
          Container(
            padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: _slate100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Histórico',
                        style: TextStyle(
                          fontSize: 12,
                          color: _slate600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: _slate400,
                    ),
                    Text(
                      widget.nomeLista,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _slate900,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                      color: _slate900,
                      tooltip: 'Voltar',
                      style: IconButton.styleFrom(hoverColor: _slate100),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.nomeLista,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: _slate900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 16,
                            runSpacing: 6,
                            children: [
                              _metaChip(
                                Icons.calendar_today_outlined,
                                'Criado em ${widget.createdAt}',
                              ),
                              if (widget.createdByEmail != null &&
                                  widget.createdByEmail!.isNotEmpty)
                                _metaChip(
                                  Icons.person_outline_rounded,
                                  widget.createdByEmail!,
                                ),
                              if (widget.reviewedByEmail != null &&
                                  widget.reviewedByEmail!.isNotEmpty) ...[
                                _metaChip(
                                  Icons.rate_review_outlined,
                                  '${_reviewLabel(widget.status)} em ${widget.reviewedAt}',
                                ),
                                _metaChip(
                                  Icons.verified_user_outlined,
                                  widget.reviewedByEmail!,
                                ),
                              ],
                              // ── Vigência ──────────────────────────────
                              if (_fmtSapDate(widget.vigenciaDatab) != null ||
                                  _fmtSapDate(widget.vigenciaDatbi) != null)
                                _metaChip(
                                  Icons.date_range_outlined,
                                  () {
                                    final ini = _fmtSapDate(
                                      widget.vigenciaDatab,
                                    );
                                    final fim = _fmtSapDate(
                                      widget.vigenciaDatbi,
                                    );
                                    if (ini != null && fim != null)
                                      return 'Vigência: $ini → $fim';
                                    if (ini != null)
                                      return 'Vigência a partir de $ini';
                                    return 'Vigência até $fim';
                                  }(),
                                  color: const Color(0xFF0369A1),
                                ),
                              // ── Justificativa ─────────────────────────
                              if (widget.justificativa != null &&
                                  widget.justificativa!.trim().isNotEmpty)
                                _metaChip(
                                  Icons.notes_rounded,
                                  widget.justificativa!.trim(),
                                  color: const Color(0xFF6D28D9),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: statusFg,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _laranja),
                  )
                : _erro.isNotEmpty
                ? _erroWidget()
                : _corpo(),
          ),
        ],
      ),
    );
  }

  Widget _corpo() {
    final kpis = _kpis();
    final grupos = _gruposOrdenados();
    final linhas = _montarLinhas(grupos);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _KpiRow(kpis: kpis),
                if (_resumo.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _RegrasBox(texto: _resumo),
                ],
                const SizedBox(height: 12),
                _FiltrosBarra(
                  materiais: _materiais,
                  filtroTab: _filtroTab,
                  busca: _busca,
                  onFiltroTab: (v) => setState(() => _filtroTab = v),
                  onBusca: (v) => setState(() => _busca = v),
                  onExportar: _exportarExcel,
                ),
                const SizedBox(height: 12),
                if (linhas.isEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _slate200),
                    ),
                    child: const Center(
                      heightFactor: 4,
                      child: Text(
                        'Nenhum material encontrado no rascunho.',
                        style: TextStyle(
                          color: _slate600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                else
                  _TabelaCabecalho(),
              ],
            ),
          ),
        ),
        if (linhas.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
            // Virtualizado: só constrói as linhas realmente visíveis na
            // tela (grupos fechados nem entram em `linhas`). É isso que
            // resolve a lentidão de carregamento/scroll com listas grandes.
            sliver: SliverList.builder(
              itemCount: linhas.length,
              itemBuilder: (context, index) {
                final linha = linhas[index];
                return switch (linha) {
                  _HeaderLinha() => _GrupoHeader(
                    tipoLista: linha.tipoLista,
                    nomeLista: linha.nomeLista,
                    alterados: linha.alterados,
                    total: linha.total,
                    onToggle: () => setState(() {
                      _listasExpandidas.contains(linha.chave)
                          ? _listasExpandidas.remove(linha.chave)
                          : _listasExpandidas.add(linha.chave);
                    }),
                    expandido: _listasExpandidas.contains(linha.chave),
                  ),
                  _VaziaLinha() => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nenhum material correspondente nesta ramificação.',
                      style: TextStyle(
                        color: _slate600,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  _ItemLinha() => _LinhaItem(
                    item: linha.item,
                    preview:
                        _previewByKey['${linha.item['product_id']}|${linha.item['lista_id']}'],
                  ),
                };
              },
            ),
          ),
      ],
    );
  }

  /// Achata grupos (lista mãe/filhas) + itens em uma lista única, incluindo
  /// só as linhas de grupos expandidos — o que fica de fora não é
  /// construído pelo SliverList.
  List<_Linha> _montarLinhas(
    List<MapEntry<String, List<Map<String, dynamic>>>> grupos,
  ) {
    final linhas = <_Linha>[];
    for (final entry in grupos) {
      final chave = entry.key;
      final grupo = entry.value;
      final filtrados = _filtrar(grupo);
      if (filtrados.isEmpty && _busca.isNotEmpty) continue;
      if (filtrados.isEmpty &&
          _filtroTab != 'todos' &&
          _filtroTab != 'sem_alteracao') {
        continue;
      }
      final meta = grupo.first;
      linhas.add(
        _HeaderLinha(
          chave: chave,
          tipoLista: meta['tipo_lista'] as String,
          nomeLista: meta['lista_nome'] as String,
          alterados: grupo.where((m) => m['foi_editado'] == true).length,
          total: grupo.length,
        ),
      );
      if (_listasExpandidas.contains(chave)) {
        if (filtrados.isEmpty) {
          linhas.add(_VaziaLinha());
        } else {
          for (final item in filtrados) {
            linhas.add(_ItemLinha(item: item));
          }
        }
      }
    }
    return linhas;
  }

  Widget _erroWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 44,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 12),
          const Text(
            'Erro ao carregar detalhes',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: _slate900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(_erro, style: const TextStyle(fontSize: 12, color: _slate600)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _carregar,
            style: ElevatedButton.styleFrom(
              backgroundColor: _laranja,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Tentar novamente',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, {Color? color}) {
    final c = color ?? _slate600;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  String _reviewLabel(String status) => switch (status) {
    'approved' => 'Aprovado',
    'rejected' => 'Rejeitado',
    _ => 'Revisado',
  };

  /// Converte YYYYMMDD → DD/MM/AAAA. Retorna null se inválido ou vazio.
  String? _fmtSapDate(String? s) {
    if (s == null || s.length < 8) return null;
    if (s == '99991231') return 'em aberto';
    return '${s.substring(6, 8)}/${s.substring(4, 6)}/${s.substring(0, 4)}';
  }
}

class _KpisSummary {
  final int total, alterados, semAlteracao, excecoes, listasFilhas;
  _KpisSummary({
    required this.total,
    required this.alterados,
    required this.semAlteracao,
    required this.excecoes,
    required this.listasFilhas,
  });
}

class _KpiRow extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  static const _slate600 = Color(0xFF475569);
  static const _slate200 = Color(0xFFE2E8F0);
  final _KpisSummary kpis;
  const _KpiRow({required this.kpis});

  @override
  Widget build(BuildContext context) {
    final pctAlt = kpis.total > 0 ? kpis.alterados / kpis.total * 100 : 0.0;
    final pctSem = kpis.total > 0 ? kpis.semAlteracao / kpis.total * 100 : 0.0;

    return Row(
      children: [
        Expanded(
          child: _card(
            Icons.inventory_2_outlined,
            'Total',
            '${kpis.total}',
            'materiais avaliados',
            Colors.blue.shade600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _card(
            Icons.edit_document,
            'Alterados',
            '${kpis.alterados}',
            '${pctAlt.toStringAsFixed(1)}% do lote',
            _laranja,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _card(
            Icons.remove_circle_outline_rounded,
            'Sem alteração',
            '${kpis.semAlteracao}',
            '${pctSem.toStringAsFixed(1)}% mantidos',
            _slate600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _card(
            Icons.rule_folder_outlined,
            'Exceções',
            '${kpis.excecoes}',
            '${kpis.listasFilhas} sub-listas filhas',
            Colors.purple.shade600,
          ),
        ),
      ],
    );
  }

  static Widget _card(
    IconData icon,
    String label,
    String valor,
    String sub,
    Color cor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: cor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _slate600,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: cor,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 10,
              color: _slate600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegrasBox extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate200 = Color(0xFFE2E8F0);
  final String texto;
  const _RegrasBox({required this.texto});

  @override
  Widget build(BuildContext context) {
    final linhas = texto.split('\n').where((l) => l.isNotEmpty);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: _slate600),
              const SizedBox(width: 8),
              Text(
                'Parâmetros e Regras de Negócio Aplicadas',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: _slate900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...linhas.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 4, color: _laranja),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: _slate600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltrosBarra extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  static const _slate600 = Color(0xFF475569);
  static const _slate400 = Color(0xFF94A3B8);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _bgSuave = Color(0xFFF8FAFC);
  final List<Map<String, dynamic>> materiais;
  final String filtroTab;
  final String busca;
  final void Function(String) onFiltroTab;
  final void Function(String) onBusca;
  final VoidCallback onExportar;

  const _FiltrosBarra({
    required this.materiais,
    required this.filtroTab,
    required this.busca,
    required this.onFiltroTab,
    required this.onBusca,
    required this.onExportar,
  });

  static String _statusLabel(Map<String, dynamic> item) {
    if (item['foi_editado'] != true) return 'Sem alteração';
    final origem = item['origem']?.toString() ?? '';
    if (origem.startsWith('Reajuste')) return 'Exceção manual';
    return 'Alterado';
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ('todos', 'Todos', materiais.length),
      (
        'alterados',
        'Alterados',
        materiais.where((m) => m['foi_editado'] == true).length,
      ),
      (
        'sem_alteracao',
        'Sem alteração',
        materiais.where((m) => m['foi_editado'] != true).length,
      ),
      (
        'excecoes',
        'Exceções',
        materiais.where((m) => _statusLabel(m) == 'Exceção manual').length,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _slate200),
      ),
      child: Row(
        children: [
          ...tabs.map((t) {
            final active = filtroTab == t.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text('${t.$2} (${t.$3})'),
                selected: active,
                onSelected: (_) => onFiltroTab(t.$1),
                selectedColor: _laranja.withOpacity(0.08),
                checkmarkColor: _laranja,
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? _laranja : _slate600,
                ),
                side: BorderSide(
                  color: active ? _laranja.withOpacity(0.5) : _slate200,
                  width: active ? 1.5 : 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }),
          const Spacer(),
          SizedBox(
            width: 280,
            height: 40,
            child: TextField(
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Buscar código ou material...',
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: _slate400,
                  fontWeight: FontWeight.w500,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: _slate600,
                ),
                isDense: true,
                filled: true,
                fillColor: _bgSuave,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _slate200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _laranja, width: 1.5),
                ),
              ),
              onChanged: onBusca,
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: onExportar,
            icon: const Icon(Icons.download_rounded, size: 16, color: _laranja),
            label: const Text(
              'Exportar Excel',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _laranja),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _laranja.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uma linha "achatada" da tabela: cabeçalho de grupo, item ou aviso de
/// grupo vazio. Permite montar a tabela toda como uma lista única e
/// virtualizá-la com SliverList.builder.
sealed class _Linha {}

class _HeaderLinha extends _Linha {
  final String chave;
  final String tipoLista;
  final String nomeLista;
  final int alterados;
  final int total;
  _HeaderLinha({
    required this.chave,
    required this.tipoLista,
    required this.nomeLista,
    required this.alterados,
    required this.total,
  });
}

class _VaziaLinha extends _Linha {}

class _ItemLinha extends _Linha {
  final Map<String, dynamic> item;
  _ItemLinha({required this.item});
}

class _TabelaCabecalho extends StatelessWidget {
  static const _slate200 = Color(0xFFE2E8F0);
  static const _bgSuave = Color(0xFFF8FAFC);
  static const _slate600 = Color(0xFF475569);

  const _TabelaCabecalho();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bgSuave,
        border: Border.all(color: _slate200),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          _th('Código', flex: 2),
          _th('Material / Descrição', flex: 5),
          _th('Vínculo', flex: 3),
          _th('Preço Anterior', flex: 2, align: TextAlign.right),
          _th('Preço Atual', flex: 2, align: TextAlign.right),
          _th('Dif. R\$', flex: 2, align: TextAlign.right),
          _th('Dif. %', flex: 2, align: TextAlign.right),
          _th('Resultado', flex: 3, align: TextAlign.center),
        ],
      ),
    );
  }

  static Widget _th(
    String label, {
    required int flex,
    TextAlign align = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: _slate600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _GrupoHeader extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _slate100 = Color(0xFFF1F5F9);
  final String tipoLista;
  final String nomeLista;
  final int alterados;
  final int total;
  final bool expandido;
  final VoidCallback onToggle;

  const _GrupoHeader({
    required this.tipoLista,
    required this.nomeLista,
    required this.alterados,
    required this.total,
    required this.expandido,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cor = tipoLista == 'mae' ? _laranja : Colors.blue.shade700;

    return Material(
      color: expandido ? cor.withOpacity(0.04) : _slate100.withOpacity(0.4),
      child: InkWell(
        onTap: onToggle,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _slate100)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Icon(
                expandido
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 20,
                color: cor,
              ),
              const SizedBox(width: 8),
              Icon(
                tipoLista == 'mae'
                    ? Icons.table_chart_outlined
                    : Icons.account_tree_outlined,
                size: 16,
                color: cor,
              ),
              const SizedBox(width: 8),
              Text(
                tipoLista == 'mae' ? 'Lista Mãe' : 'Lista Filha',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: cor,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nomeLista,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _slate900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _slate200),
                ),
                child: Text(
                  '$alterados/$total alterados',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _slate600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinhaItem extends StatefulWidget {
  final Map<String, dynamic> item;
  final MaterialDraftPreview? preview;
  const _LinhaItem({required this.item, this.preview});

  @override
  State<_LinhaItem> createState() => _LinhaItemState();
}

class _LinhaItemState extends State<_LinhaItem> {
  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate100 = Color(0xFFF1F5F9);

  bool _expandido = false;

  static String _statusLabel(Map<String, dynamic> item) {
    if (item['foi_editado'] != true) return 'Sem alteração';
    final origem = item['origem']?.toString() ?? '';
    if (origem.startsWith('Reajuste')) return 'Exceção manual';
    return 'Alterado';
  }

  static String _fmt(double v) {
    final abs = v.abs().toStringAsFixed(2).replaceAll('.', ',');
    return '${v < 0 ? '-R\$ ' : 'R\$ '}$abs';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final antigo = (item['preco_antigo'] as num).toDouble();
    final novo = (item['preco_novo'] as num).toDouble();
    final dif = novo - antigo;
    final pct = antigo > 0 ? (dif / antigo) * 100 : 0.0;
    final status = _statusLabel(item);
    final alterado = item['foi_editado'] == true;
    final temPreview = widget.preview != null;

    final difColor = dif > 0
        ? const Color(0xFF047857)
        : dif < 0
        ? const Color(0xFFB91C1C)
        : _slate600;

    return Column(
      children: [
        Material(
          color: alterado ? _laranja.withOpacity(0.015) : Colors.white,
          child: InkWell(
            onTap: temPreview
                ? () => setState(() => _expandido = !_expandido)
                : null,
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _slate100)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    child: temPreview
                        ? Icon(
                            _expandido
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.keyboard_arrow_right_rounded,
                            size: 18,
                            color: _slate600,
                          )
                        : null,
                  ),
                  _td(
                    item['product_id'].toString(),
                    flex: 2,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: _slate600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _td(
                    item['description'].toString(),
                    flex: 5,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _slate900,
                    ),
                  ),
                  _td(
                    item['lista_nome'].toString(),
                    flex: 3,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _slate600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  _td(
                    _fmt(antigo),
                    flex: 2,
                    align: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: alterado ? _slate600 : _slate900,
                      decoration: alterado ? TextDecoration.lineThrough : null,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  _td(
                    _fmt(novo),
                    flex: 2,
                    align: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: alterado ? FontWeight.w900 : FontWeight.w600,
                      color: alterado ? _slate900 : _slate600,
                    ),
                  ),
                  _td(
                    '${dif >= 0 ? '+' : ''}${_fmt(dif)}',
                    flex: 2,
                    align: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: difColor,
                    ),
                  ),
                  _td(
                    '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                    flex: 2,
                    align: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: difColor,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Center(child: _Badge(status: status)),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expandido && widget.preview != null)
          Container(
            color: const Color(0xFFF8FAFC),
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: MaterialPrecoCardView(m: widget.preview!.toMaterialPreco()),
          ),
      ],
    );
  }

  static Widget _td(
    String text, {
    required int flex,
    TextAlign align = TextAlign.left,
    TextStyle? style,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: align,
        style: style,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String status;
  const _Badge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'Alterado' => (const Color(0xFFECFDF5), const Color(0xFF047857)),
      'Exceção manual' => (const Color(0xFFF3E8FF), const Color(0xFF7E22CE)),
      _ => (const Color(0xFFF1F5F9), const Color(0xFF475569)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
