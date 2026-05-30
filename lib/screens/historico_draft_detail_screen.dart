// historico_draft_detail_screen.dart
// Tela de visualização somente-leitura de um draft aprovado/rejeitado/pendente.
// Aberta a partir do HistoricoScreen ao clicar em uma linha.
// Reutiliza os mesmos widgets de detalhes da AprovacoesScreen, mas sem botões de ação.
import 'package:flutter/material.dart';
import 'package:pole_price/service/draft_pricing_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoricoDraftDetailScreen extends StatefulWidget {
  final String draftId;
  final String nomeLista;
  final String status;
  final String? createdByEmail;
  final String? reviewedByEmail;
  final String createdAt;
  final String reviewedAt;

  const HistoricoDraftDetailScreen({
    super.key,
    required this.draftId,
    required this.nomeLista,
    required this.status,
    this.createdByEmail,
    this.reviewedByEmail,
    required this.createdAt,
    required this.reviewedAt,
  });

  @override
  State<HistoricoDraftDetailScreen> createState() =>
      _HistoricoDraftDetailScreenState();
}

class _HistoricoDraftDetailScreenState
    extends State<HistoricoDraftDetailScreen> {
  static const _laranja = Color(0xFFFF6B00);

  late final DraftPricingService _draftService;
  bool _loading = true;
  String _erro = '';

  List<Map<String, dynamic>> _materiais = [];
  String _resumo = '';
  String _filtroTab = 'todos';
  String _busca = '';
  final Set<String> _listasExpandidas = {};

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
        _resumo = preview.resumo;
        // Expande todos os grupos por padrão na visualização de histórico
        for (final m in _materiais) {
          _listasExpandidas.add(m['lista_id'] as String);
        }
      });
    } catch (e) {
      setState(() => _erro = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  (String label, Color bg, Color fg) get _statusConfig => switch (widget.status) {
        'approved' =>
          ('Aprovado', Colors.green.shade50, Colors.green.shade700),
        'rejected' => ('Rejeitado', Colors.red.shade50, Colors.red.shade700),
        _ => ('Pendente', _laranja.withOpacity(0.10), _laranja),
      };

  Map<String, List<Map<String, dynamic>>> _agruparPorLista() {
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final mat in _materiais) {
      grupos.putIfAbsent(mat['lista_id'] as String, () => []).add(mat);
    }
    return grupos;
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _gruposOrdenados() {
    return _agruparPorLista().entries.toList()
      ..sort((a, b) {
        final aMae = a.value.first['tipo_lista'] == 'mae';
        final bMae = b.value.first['tipo_lista'] == 'mae';
        if (aMae && !bMae) return -1;
        if (!aMae && bMae) return 1;
        return a.value.first['lista_nome']
            .toString()
            .compareTo(b.value.first['lista_nome'].toString());
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

  _KpisSummary _kpis() {
    final total = _materiais.length;
    final alterados = _materiais.where((m) => m['foi_editado'] == true).length;
    final excecoes = _materiais
        .where((m) => _statusLabelItem(m) == 'Exceção manual')
        .length;
    final listas = _agruparPorLista()
        .values
        .where((g) => g.first['tipo_lista'] == 'filha')
        .length;
    return _KpisSummary(
        total: total,
        alterados: alterados,
        semAlteracao: total - alterados,
        excecoes: excecoes,
        listasFilhas: listas);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusBg, statusFg) = _statusConfig;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Topbar ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Breadcrumb
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Text('Histórico',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade500)),
                    ),
                    Icon(Icons.chevron_right,
                        size: 16, color: Colors.grey.shade400),
                    Text(widget.nomeLista,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade700)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Botão voltar
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                      color: Colors.grey.shade700,
                      tooltip: 'Voltar',
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.nomeLista,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 16,
                            runSpacing: 4,
                            children: [
                              _metaChip(
                                  Icons.calendar_today_outlined,
                                  'Criado em ${widget.createdAt}'),
                              if (widget.createdByEmail != null &&
                                  widget.createdByEmail!.isNotEmpty)
                                _metaChip(Icons.person_outline,
                                    widget.createdByEmail!),
                              if (widget.reviewedByEmail != null &&
                                  widget.reviewedByEmail!.isNotEmpty) ...[
                                _metaChip(
                                    Icons.rate_review_outlined,
                                    '${_reviewLabel(widget.status)} em ${widget.reviewedAt}'),
                                _metaChip(Icons.verified_user_outlined,
                                    widget.reviewedByEmail!),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Badge de status
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(statusLabel,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: statusFg)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Corpo ────────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // KPIs + Regras
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KpiRow(kpis: kpis),
              if (_resumo.isNotEmpty) ...[
                const SizedBox(height: 10),
                _RegrasBox(texto: _resumo),
              ],
              const SizedBox(height: 10),
              _FiltrosBarra(
                materiais: _materiais,
                filtroTab: _filtroTab,
                busca: _busca,
                onFiltroTab: (v) => setState(() => _filtroTab = v),
                onBusca: (v) => setState(() => _busca = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Tabela
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: _TabelaDetalhe(
              grupos: grupos,
              listasExpandidas: _listasExpandidas,
              filtrar: _filtrar,
              busca: _busca,
              filtroTab: _filtroTab,
              onToggle: (k) => setState(() {
                _listasExpandidas.contains(k)
                    ? _listasExpandidas.remove(k)
                    : _listasExpandidas.add(k);
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _erroWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Text('Erro ao carregar detalhes',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                  fontSize: 16)),
          const SizedBox(height: 6),
          Text(_erro,
              style:
                  TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _carregar,
            style: ElevatedButton.styleFrom(
                backgroundColor: _laranja, foregroundColor: Colors.white),
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  String _reviewLabel(String status) => switch (status) {
        'approved' => 'Aprovado',
        'rejected' => 'Rejeitado',
        _ => 'Revisado',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI row
// ─────────────────────────────────────────────────────────────────────────────
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
  final _KpisSummary kpis;
  const _KpiRow({required this.kpis});

  @override
  Widget build(BuildContext context) {
    final pctAlt =
        kpis.total > 0 ? kpis.alterados / kpis.total * 100 : 0.0;
    final pctSem =
        kpis.total > 0 ? kpis.semAlteracao / kpis.total * 100 : 0.0;

    return Row(
      children: [
        Expanded(
            child: _card(Icons.inventory_2_outlined, 'Total',
                '${kpis.total}', 'materiais', Colors.blue.shade600)),
        const SizedBox(width: 10),
        Expanded(
            child: _card(Icons.edit_outlined, 'Alterados',
                '${kpis.alterados}', '${pctAlt.toStringAsFixed(1)}%', _laranja)),
        const SizedBox(width: 10),
        Expanded(
            child: _card(Icons.remove_circle_outline, 'Sem alteração',
                '${kpis.semAlteracao}', '${pctSem.toStringAsFixed(1)}%',
                Colors.grey.shade600)),
        const SizedBox(width: 10),
        Expanded(
            child: _card(Icons.rule_outlined, 'Exceções',
                '${kpis.excecoes}', '${kpis.listasFilhas} listas filhas',
                Colors.purple.shade600)),
      ],
    );
  }

  static Widget _card(
      IconData icon, String label, String valor, String sub, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: cor),
            const SizedBox(width: 6),
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 8),
          Text(valor,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cor)),
          Text(sub,
              style:
                  TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Regras box
// ─────────────────────────────────────────────────────────────────────────────
class _RegrasBox extends StatelessWidget {
  final String texto;
  const _RegrasBox({required this.texto});

  @override
  Widget build(BuildContext context) {
    final linhas = texto.split('\n').where((l) => l.isNotEmpty);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            const Text('Regras aplicadas',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          ...linhas.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.grey.shade700)),
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filtros e busca
// ─────────────────────────────────────────────────────────────────────────────
class _FiltrosBarra extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  final List<Map<String, dynamic>> materiais;
  final String filtroTab;
  final String busca;
  final void Function(String) onFiltroTab;
  final void Function(String) onBusca;

  const _FiltrosBarra({
    required this.materiais,
    required this.filtroTab,
    required this.busca,
    required this.onFiltroTab,
    required this.onBusca,
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
      ('alterados', 'Alterados',
          materiais.where((m) => m['foi_editado'] == true).length),
      ('sem_alteracao', 'Sem alteração',
          materiais.where((m) => m['foi_editado'] != true).length),
      ('excecoes', 'Exceções',
          materiais.where((m) => _statusLabel(m) == 'Exceção manual').length),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
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
                selectedColor: _laranja.withOpacity(0.12),
                checkmarkColor: _laranja,
                showCheckmark: false,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? _laranja : Colors.grey.shade700,
                ),
                side: BorderSide(
                  color: active
                      ? _laranja.withOpacity(0.4)
                      : Colors.grey.shade300,
                ),
              ),
            );
          }),
          const Spacer(),
          SizedBox(
            width: 260,
            height: 38,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar código ou material...',
                hintStyle: TextStyle(
                    fontSize: 12, color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search,
                    size: 18, color: Colors.grey.shade400),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: onBusca,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tabela de detalhe com grupos expansíveis
// ─────────────────────────────────────────────────────────────────────────────
class _TabelaDetalhe extends StatelessWidget {
  final List<MapEntry<String, List<Map<String, dynamic>>>> grupos;
  final Set<String> listasExpandidas;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>>) filtrar;
  final String busca;
  final String filtroTab;
  final void Function(String) onToggle;

  const _TabelaDetalhe({
    required this.grupos,
    required this.listasExpandidas,
    required this.filtrar,
    required this.busca,
    required this.filtroTab,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (grupos.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Center(
          child: Text('Nenhum material encontrado.',
              style: TextStyle(color: Colors.grey.shade500)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        children: [
          _cabecalho(),
          ...grupos.map((entry) {
            final chave = entry.key;
            final grupo = entry.value;
            final filtrados = filtrar(grupo);
            if (filtrados.isEmpty && busca.isNotEmpty) {
              return const SizedBox.shrink();
            }
            if (filtrados.isEmpty &&
                filtroTab != 'todos' &&
                filtroTab != 'sem_alteracao') {
              return const SizedBox.shrink();
            }
            return _GrupoExpansivel(
              chave: chave,
              grupo: grupo,
              filtrados: filtrados,
              expandido: listasExpandidas.contains(chave),
              onToggle: () => onToggle(chave),
            );
          }),
        ],
      ),
    );
  }

  static Widget _cabecalho() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.grey.shade50,
      child: Row(
        children: [
          _th('Código', flex: 2),
          _th('Material', flex: 5),
          _th('Lista', flex: 3),
          _th('Preço anterior', flex: 2, align: TextAlign.right),
          _th('Preço atual', flex: 2, align: TextAlign.right),
          _th('Dif. R\$', flex: 2, align: TextAlign.right),
          _th('Dif. %', flex: 2, align: TextAlign.right),
          _th('Status', flex: 3, align: TextAlign.center),
        ],
      ),
    );
  }

  static Widget _th(String label,
      {required int flex, TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(label,
          textAlign: align,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grupo expansível
// ─────────────────────────────────────────────────────────────────────────────
class _GrupoExpansivel extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  final String chave;
  final List<Map<String, dynamic>> grupo;
  final List<Map<String, dynamic>> filtrados;
  final bool expandido;
  final VoidCallback onToggle;

  const _GrupoExpansivel({
    required this.chave,
    required this.grupo,
    required this.filtrados,
    required this.expandido,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final meta = grupo.first;
    final tipoLista = meta['tipo_lista'] as String;
    final nomeLista = meta['lista_nome'] as String;
    final alterados = grupo.where((m) => m['foi_editado'] == true).length;
    final cor = tipoLista == 'mae' ? _laranja : Colors.blue.shade700;

    return Column(
      children: [
        Material(
          color: expandido ? cor.withOpacity(0.04) : Colors.grey.shade50,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    expandido
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
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
                    tipoLista == 'mae' ? 'Lista mãe' : 'Lista filha',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(nomeLista,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text('$alterados/${grupo.length} alterados',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600)),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expandido) ...[
          if (filtrados.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Nenhum material neste filtro.',
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 12)),
            )
          else
            ...filtrados.map((item) => _LinhaItem(item: item)),
        ],
        Divider(height: 1, color: Colors.grey.shade100),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Linha de material
// ─────────────────────────────────────────────────────────────────────────────
class _LinhaItem extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  final Map<String, dynamic> item;
  const _LinhaItem({required this.item});

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
    final antigo = (item['preco_antigo'] as num).toDouble();
    final novo = (item['preco_novo'] as num).toDouble();
    final dif = novo - antigo;
    final pct = antigo > 0 ? (dif / antigo) * 100 : 0.0;
    final status = _statusLabel(item);
    final alterado = item['foi_editado'] == true;

    final difColor = dif > 0
        ? Colors.green.shade700
        : dif < 0
            ? Colors.red.shade600
            : Colors.grey.shade500;

    return Container(
      decoration: BoxDecoration(
        color: alterado ? _laranja.withOpacity(0.02) : null,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _td(item['product_id'].toString(),
              flex: 2,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey.shade700)),
          _td(item['description'].toString(),
              flex: 5,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500)),
          _td(item['lista_nome'].toString(),
              flex: 3,
              style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          _td(_fmt(antigo),
              flex: 2,
              align: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: alterado
                    ? Colors.grey.shade500
                    : Colors.grey.shade800,
                decoration:
                    alterado ? TextDecoration.lineThrough : null,
              )),
          _td(_fmt(novo),
              flex: 2,
              align: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    alterado ? FontWeight.bold : FontWeight.normal,
                color: alterado
                    ? Colors.grey.shade900
                    : Colors.grey.shade700,
              )),
          _td('${dif >= 0 ? '+' : ''}${_fmt(dif)}',
              flex: 2,
              align: TextAlign.right,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: difColor)),
          _td(
              '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
              flex: 2,
              align: TextAlign.right,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: difColor)),
          Expanded(flex: 3, child: Center(child: _Badge(status: status))),
        ],
      ),
    );
  }

  static Widget _td(String text,
      {required int flex,
      TextAlign align = TextAlign.left,
      TextStyle? style}) {
    return Expanded(
      flex: flex,
      child: Text(text,
          textAlign: align,
          style: style ?? const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
          maxLines: 2),
    );
  }
}

class _Badge extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  final String status;
  const _Badge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'Alterado' => (Colors.green.shade50, Colors.green.shade700),
      'Exceção manual' => (_laranja.withOpacity(0.12), _laranja),
      _ => (Colors.grey.shade100, Colors.grey.shade600),
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg)),
    );
  }
}