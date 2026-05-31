// relatorio_screen.dart
// Tela de relatório: seleciona lista de preço e visualiza histórico de mudanças
// de preço por material. Reconstrói o histórico a partir dos price_draft_items
// de drafts aprovados (reviewed_at = data da mudança efetiva).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modelos internos
// ─────────────────────────────────────────────────────────────────────────────
class _PontoHistorico {
  final DateTime data;
  final double preco;
  final double? precoAnterior;
  final String draftId;

  _PontoHistorico({
    required this.data,
    required this.preco,
    this.precoAnterior,
    required this.draftId,
  });
}

class _SerieHistorico {
  final String productId;
  final String description;
  final List<_PontoHistorico> pontos; // ordenados por data asc

  _SerieHistorico({
    required this.productId,
    required this.description,
    required this.pontos,
  });

  double get precoInicial => pontos.first.preco;
  double get precoFinal => pontos.last.preco;
  double get variacaoAbsoluta => precoFinal - precoInicial;
  double get variacaoPct =>
      precoInicial > 0 ? (variacaoAbsoluta / precoInicial) * 100 : 0;
}

class _ListaPrecoRef {
  final String id;
  final String description;
  _ListaPrecoRef({required this.id, required this.description});
}

// ─────────────────────────────────────────────────────────────────────────────
// Tela Principal
// ─────────────────────────────────────────────────────────────────────────────
class RelatorioScreen extends StatefulWidget {
  const RelatorioScreen({super.key});

  @override
  State<RelatorioScreen> createState() => _RelatorioScreenState();
}

class _RelatorioScreenState extends State<RelatorioScreen> {
  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _slate100 = Color(0xFFF1F5F9);
  static const _bgSuave = Color(0xFFF8FAFC);

  final _supabase = Supabase.instance.client;

  bool _loadingListas = true;
  bool _loadingDados = false;

  List<_ListaPrecoRef> _listas = [];
  String? _listaSelecionadaId;

  List<_SerieHistorico> _todasSeries = [];
  List<_SerieHistorico> _seriesFiltradas = [];
  _SerieHistorico? _serieAtiva;

  String _buscaProduto = '';

  @override
  void initState() {
    super.initState();
    _carregarListas();
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  Future<void> _carregarListas() async {
    setState(() => _loadingListas = true);
    try {
      final res = await _supabase
          .from('price_lists')
          .select('id, description')
          .order('description');
      setState(() {
        _listas = (res as List)
            .map((row) => _ListaPrecoRef(
                  id: row['id'] as String,
                  description: row['description'] as String,
                ))
            .toList();
        _loadingListas = false;
      });
    } catch (e) {
      _snack('Erro ao carregar listas: $e', erro: true);
      setState(() => _loadingListas = false);
    }
  }

  Future<void> _processarHistorico(String listaId) async {
    setState(() {
      _loadingDados = true;
      _todasSeries = [];
      _seriesFiltradas = [];
      _serieAtiva = null;
    });

    try {
      // 1. Busca todos os drafts aprovados desta lista
      final draftsRes = await _supabase
          .from('price_drafts')
          .select('id, reviewed_at')
          .eq('master_list_id', listaId)
          .eq('status', 'approved')
          .order('reviewed_at');

      final drafts = (draftsRes as List).cast<Map<String, dynamic>>();

      if (drafts.isEmpty) {
        setState(() => _loadingDados = false);
        return;
      }

      // Monta mapa de datas ignorando reviewed_at nulos
      final Map<String, DateTime> datasPorDraft = {};
      for (final d in drafts) {
        final rawDate = d['reviewed_at']?.toString();
        if (rawDate == null || rawDate == 'null') continue;
        datasPorDraft[d['id'].toString()] =
            DateTime.parse(rawDate).toLocal();
      }

      final draftIds = datasPorDraft.keys.toList();
      if (draftIds.isEmpty) {
        setState(() => _loadingDados = false);
        return;
      }

      // 2. Busca todos os itens desses drafts em batch
      final itensRes = await _supabase
          .from('price_draft_items')
          .select('draft_id, product_id, old_price, new_price')
          .inFilter('draft_id', draftIds);

      // 3. Busca descriptions dos materiais desta lista
      final matsRes = await _supabase
          .from('materials')
          .select('product_id, description')
          .eq('price_list_id', listaId);

      final Map<String, String> descricoes = {
        for (final m in matsRes as List)
          m['product_id'].toString(): m['description']?.toString() ?? '',
      };

      // 4. Monta séries por product_id
      final Map<String, List<_PontoHistorico>> porProduto = {};
      for (final item in itensRes as List) {
        final draftId = item['draft_id']?.toString();
        final pid = item['product_id']?.toString();
        final preco = _toDouble(item['new_price']);
        final precoAnterior = _toDouble(item['old_price']);
        if (draftId == null || pid == null || preco == null) continue;
        final data = datasPorDraft[draftId];
        if (data == null) continue;

        porProduto.putIfAbsent(pid, () => []).add(
              _PontoHistorico(
                data: data,
                preco: preco,
                precoAnterior: precoAnterior,
                draftId: draftId,
              ),
            );
      }

      // 5. Ordena pontos por data e cria séries
      final listSeries = porProduto.entries.map((e) {
        final pts = e.value..sort((a, b) => a.data.compareTo(b.data));
        return _SerieHistorico(
          productId: e.key,
          description: descricoes[e.key] ?? e.key,
          pontos: pts,
        );
      }).toList()
        ..sort(
            (a, b) => b.variacaoPct.abs().compareTo(a.variacaoPct.abs()));

      setState(() {
        _todasSeries = listSeries;
        _filtrarLocal(busca: _buscaProduto);
        if (_seriesFiltradas.isNotEmpty) {
          _serieAtiva = _seriesFiltradas.first;
        }
        _loadingDados = false;
      });
    } catch (e) {
      _snack('Erro ao processar dados: $e', erro: true);
      setState(() => _loadingDados = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  void _filtrarLocal({required String busca}) {
    _buscaProduto = busca;
    if (busca.trim().isEmpty) {
      _seriesFiltradas = List.from(_todasSeries);
    } else {
      final b = busca.toLowerCase();
      _seriesFiltradas = _todasSeries.where((s) {
        return s.productId.toLowerCase().contains(b) ||
            s.description.toLowerCase().contains(b);
      }).toList();
    }
  }

  void _snack(String msg, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? Colors.red : Colors.green,
      ),
    );
  }

  String _formatarDataCompleta(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final a = local.year;
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$a $h:$min';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgSuave,
      body: Column(
        children: [
          _topBarPremium(),
          Expanded(
            child: _loadingListas
                ? const Center(
                    child: CircularProgressIndicator(color: _laranja))
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 320, child: _sidebarFiltros()),
                        const SizedBox(width: 24),
                        Expanded(child: _painelDashboardCentral()),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _topBarPremium() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Color(0x02000000),
              blurRadius: 15,
              offset: Offset(0, 4))
        ],
        border: Border(bottom: BorderSide(color: _slate100)),
      ),
      child: const Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Business Intelligence & Auditoria',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _slate900,
                    letterSpacing: -0.5),
              ),
              Text(
                'Rastreabilidade temporal de margens e volatilidade de preços',
                style: TextStyle(
                    fontSize: 12,
                    color: _slate600,
                    fontWeight: FontWeight.w500),
              )
            ],
          ),
        ],
      ),
    );
  }

  // ── Sidebar ───────────────────────────────────────────────────────────────

  Widget _sidebarFiltros() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _slate200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ESTRUTURA DE PRECIFICAÇÃO',
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w800,
                    color: _slate600),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _listaSelecionadaId,
                hint: const Text('Selecione uma tabela...',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                isExpanded: true,
                decoration: InputDecoration(
                  fillColor: _bgSuave,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _slate200)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _laranja)),
                ),
                items: _listas.map((l) {
                  return DropdownMenuItem(
                    value: l.id,
                    child: Text(l.description,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _slate900)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _listaSelecionadaId = val);
                    _processarHistorico(val);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _slate200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: TextField(
                    onChanged: (v) => setState(() {
                      _filtrarLocal(busca: v);
                    }),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Buscar SKU ou descrição...',
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 18, color: _slate600),
                      isDense: true,
                      filled: true,
                      fillColor: _bgSuave,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: _slate200)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: _laranja)),
                    ),
                  ),
                ),
                const Divider(height: 1, color: _slate100),
                Expanded(
                  child: _loadingDados
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: _laranja))
                      : _seriesFiltradas.isEmpty
                          ? Center(
                              child: Text('Nenhum registro ativo',
                                  style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 13)))
                          : ListView.separated(
                              itemCount: _seriesFiltradas.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(
                                      height: 1, color: _slate100),
                              padding: EdgeInsets.zero,
                              itemBuilder: (context, i) {
                                final s = _seriesFiltradas[i];
                                final ativo =
                                    _serieAtiva?.productId ==
                                        s.productId;
                                final corPct = s.variacaoPct > 0
                                    ? const Color(0xFF10B981)
                                    : (s.variacaoPct < 0
                                        ? const Color(0xFFEF4444)
                                        : _slate600);

                                return InkWell(
                                  onTap: () => setState(
                                      () => _serieAtiva = s),
                                  child: AnimatedContainer(
                                    duration: const Duration(
                                        milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 14),
                                    color: ativo
                                        ? _laranja.withOpacity(0.03)
                                        : Colors.transparent,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                s.description,
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: ativo
                                                        ? FontWeight.w800
                                                        : FontWeight.w600,
                                                    color: _slate900),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'REF: ${s.productId}',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    fontFamily: 'monospace',
                                                    color: Colors
                                                        .grey.shade400,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets
                                              .symmetric(
                                              horizontal: 8,
                                              vertical: 4),
                                          decoration: BoxDecoration(
                                              color: corPct
                                                  .withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      8)),
                                          child: Text(
                                            '${s.variacaoPct > 0 ? '+' : ''}${s.variacaoPct.toStringAsFixed(1)}%',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: corPct),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Painel central ────────────────────────────────────────────────────────

  Widget _painelDashboardCentral() {
    if (_listaSelecionadaId == null) {
      return _buildEstadoVazio(
          'Selecione uma estrutura comercial',
          'Escolha uma tabela operacional no painel esquerdo para gerar os modelos temporais.',
          Icons.analytics_outlined);
    }
    if (_loadingDados) {
      return const Center(
          child: CircularProgressIndicator(color: _laranja));
    }
    if (_todasSeries.isEmpty) {
      return _buildEstadoVazio(
          'Sem movimentações catalogadas',
          'Esta lista de preço não possui históricos ou alterações submetidas via rascunho até o momento.',
          Icons.auto_graph_rounded);
    }

    final maiorAlta = _todasSeries.firstWhere(
        (s) => s.variacaoPct > 0,
        orElse: () => _todasSeries.first);
    final maiorQueda = _todasSeries.lastWhere((s) => s.variacaoPct < 0,
        orElse: () => _todasSeries.last);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── RIBBON DE KPIS ──
          Row(
            children: [
              _kpiCardDashboard(
                title: 'MATERIAIS MONITORADOS',
                value: '${_todasSeries.length} SKUs',
                sub: 'Auditados em tempo real',
                icon: Icons.inventory_2_outlined,
                bg: const Color(0xFFEFF6FF),
                fg: const Color(0xFF1D4ED8),
              ),
              const SizedBox(width: 16),
              _kpiCardDashboard(
                title: 'MAIOR VOLATILIDADE',
                value:
                    '${maiorAlta.variacaoPct.toStringAsFixed(1)}%',
                sub: maiorAlta.description,
                icon: Icons.trending_up_rounded,
                bg: const Color(0xFFECFDF5),
                fg: const Color(0xFF047857),
              ),
              const SizedBox(width: 16),
              _kpiCardDashboard(
                title: 'ESTABILIDADE DE PREÇO',
                value:
                    '${maiorQueda.variacaoPct.toStringAsFixed(1)}%',
                sub: maiorQueda.description,
                icon: Icons.trending_down_rounded,
                bg: const Color(0xFFFFF1F2),
                fg: const Color(0xFFB91C1C),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── GRÁFICO ──
          if (_serieAtiva != null) ...[
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _slate200),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x02000000), blurRadius: 20)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(_serieAtiva!.description,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: _slate900,
                                    letterSpacing: -0.5)),
                            const SizedBox(height: 4),
                            Text(
                                'ID Único do Material: ${_serieAtiva!.productId}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: _slate600,
                                    fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('PREÇO ATUAL COMERCIAL',
                              style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 0.6,
                                  fontWeight: FontWeight.bold,
                                  color: _slate600)),
                          Text(
                              'R\$ ${_serieAtiva!.precoFinal.toStringAsFixed(2).replaceAll('.', ',')}',
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: _slate900)),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 32),
                  Container(
                    height: 260,
                    width: double.infinity,
                    padding:
                        const EdgeInsets.only(right: 16, top: 12),
                    child: CustomPaint(
                      painter: _PremiumChartPainter(
                          serie: _serieAtiva!),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── TABELA DE AUDITORIA ──
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _slate200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Trilha de Auditoria Técnica (Rascunhos Aprovados)',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _slate900)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    color: _bgSuave,
                    child: Row(
                      children: [
                        Expanded(
                            flex: 3,
                            child: _gridHeaderLabel(
                                'DATA DA MUDANÇA')),
                        Expanded(
                            flex: 3,
                            child: _gridHeaderLabel(
                                'PREÇO ANTERIOR')),
                        Expanded(
                            flex: 3,
                            child: _gridHeaderLabel(
                                'NOVO VALOR BASE')),
                        Expanded(
                            flex: 2,
                            child:
                                _gridHeaderLabel('VARIAÇÃO LIQ.')),
                        Expanded(
                            flex: 4,
                            child: _gridHeaderLabel(
                                'PROTOCOLO/DRAFT ID',
                                align: TextAlign.right)),
                      ],
                    ),
                  ),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _serieAtiva!.pontos.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: _slate100),
                    itemBuilder: (context, idx) {
                      final p = _serieAtiva!.pontos[idx];

                      // Usa old_price do item; fallback para o ponto anterior
                      final anterior = p.precoAnterior ??
                          (idx > 0
                              ? _serieAtiva!.pontos[idx - 1].preco
                              : null);

                      double? diffPct;
                      if (anterior != null && anterior > 0) {
                        diffPct =
                            ((p.preco - anterior) / anterior) * 100;
                      }

                      final corBadge = diffPct == null ||
                              diffPct == 0
                          ? _slate600
                          : (diffPct > 0
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444));

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        child: Row(
                          children: [
                            Expanded(
                                flex: 3,
                                child: Text(
                                    _formatarDataCompleta(p.data),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _slate900))),
                            Expanded(
                              flex: 3,
                              child: Text(
                                anterior != null
                                    ? 'R\$ ${anterior.toStringAsFixed(2).replaceAll('.', ',')}'
                                    : '—',
                                style: const TextStyle(
                                    fontSize: 13, color: _slate600),
                              ),
                            ),
                            Expanded(
                                flex: 3,
                                child: Text(
                                    'R\$ ${p.preco.toStringAsFixed(2).replaceAll('.', ',')}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _slate900))),
                            Expanded(
                              flex: 2,
                              child: diffPct == null
                                  ? const Text('Base',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: _slate600))
                                  : Text(
                                      '${diffPct > 0 ? '+' : ''}${diffPct.toStringAsFixed(1)}%',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: corBadge),
                                    ),
                            ),
                            Expanded(
                              flex: 4,
                              child: Text(
                                p.draftId,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: _slate600,
                                    fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Widgets auxiliares ────────────────────────────────────────────────────

  Widget _kpiCardDashboard({
    required String title,
    required String value,
    required String sub,
    required IconData icon,
    required Color bg,
    required Color fg,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _slate200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: fg, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade400)),
                  const SizedBox(height: 4),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: _slate900,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 12,
                          color: _slate600,
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _gridHeaderLabel(String label,
      {TextAlign align = TextAlign.left}) {
    return Text(label,
        textAlign: align,
        style: const TextStyle(
            fontSize: 11,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w800,
            color: _slate600));
  }

  Widget _buildEstadoVazio(String t, String s, IconData icon) {
    return Container(
      width: double.infinity,
      height: 400,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _slate200)),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                  color: _bgSuave, shape: BoxShape.circle),
              child:
                  Icon(icon, size: 44, color: Colors.grey.shade300),
            ),
            const SizedBox(height: 16),
            Text(t,
                style: const TextStyle(
                    color: _slate900,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            SizedBox(
              width: 400,
              child: Text(s,
                  style: const TextStyle(
                      color: _slate600, fontSize: 13, height: 1.4),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Painter Estilizado
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumChartPainter extends CustomPainter {
  final _SerieHistorico serie;
  _PremiumChartPainter({required this.serie});

  @override
  void paint(Canvas canvas, Size size) {
    final pontos = serie.pontos;
    if (pontos.isEmpty) return;

    final precos = pontos.map((p) => p.preco).toList();
    double minPreco = precos.reduce((a, b) => a < b ? a : b);
    double maxPreco = precos.reduce((a, b) => a > b ? a : b);

    if (maxPreco == minPreco) {
      maxPreco += 10;
      minPreco -= 10;
    } else {
      final padding = (maxPreco - minPreco) * 0.15;
      maxPreco += padding;
      minPreco -= padding;
    }

    if (minPreco < 0) minPreco = 0;

    final paintGrid = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = 1.2;

    final paintLinhaPrincipal = Paint()
      ..color = const Color(0xFFFF6B00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final paintPontoCompleto = Paint()
      ..color = const Color(0xFFFF6B00)
      ..style = PaintingStyle.fill;

    final paintPontoInterno = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    const totalGrids = 4;
    for (int i = 0; i <= totalGrids; i++) {
      final y = size.height * (i / totalGrids);
      canvas.drawLine(Offset(45, y), Offset(size.width, y), paintGrid);

      final valorY =
          maxPreco - ((maxPreco - minPreco) * (i / totalGrids));
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'R\$ ${valorY.toStringAsFixed(0)}',
          style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(0, y - 6));
    }

    final deparamentoPontos = <Offset>[];
    final stepX = pontos.length > 1
        ? (size.width - 60) / (pontos.length - 1)
        : size.width - 60;

    for (int i = 0; i < pontos.length; i++) {
      final p = pontos[i];
      final x = 55 + (i * stepX);
      final pctY = (p.preco - minPreco) / (maxPreco - minPreco);
      final y = size.height * (1 - pctY);
      deparamentoPontos.add(Offset(x, y));
    }

    if (deparamentoPontos.length > 1) {
      final pathGradiente = Path()
        ..moveTo(deparamentoPontos.first.dx, size.height);
      for (final pt in deparamentoPontos) {
        pathGradiente.lineTo(pt.dx, pt.dy);
      }
      pathGradiente.lineTo(deparamentoPontos.last.dx, size.height);
      pathGradiente.close();

      final paintSombra = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFF6B00).withOpacity(0.12),
            const Color(0xFFFF6B00).withOpacity(0.00),
          ],
        ).createShader(
            Rect.fromLTWH(0, 0, size.width, size.height));

      canvas.drawPath(pathGradiente, paintSombra);
    }

    if (deparamentoPontos.length > 1) {
      final pathLinha = Path()
        ..moveTo(deparamentoPontos.first.dx,
            deparamentoPontos.first.dy);
      for (int i = 1; i < deparamentoPontos.length; i++) {
        pathLinha.lineTo(
            deparamentoPontos[i].dx, deparamentoPontos[i].dy);
      }
      canvas.drawPath(pathLinha, paintLinhaPrincipal);
    }

    for (int i = 0; i < deparamentoPontos.length; i++) {
      final pt = deparamentoPontos[i];
      final p = pontos[i];

      canvas.drawCircle(pt, 5.5, paintPontoCompleto);
      canvas.drawCircle(pt, 2.5, paintPontoInterno);

      if (i == 0 ||
          i == deparamentoPontos.length - 1 ||
          deparamentoPontos.length <= 6) {
        final labelData =
            '${p.data.day.toString().padLeft(2, '0')}/${p.data.month.toString().padLeft(2, '0')}';
        final txtDataPainter = TextPainter(
          text: TextSpan(
            text: labelData,
            style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 10,
                fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        txtDataPainter.paint(
            canvas, Offset(pt.dx - 12, size.height + 8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PremiumChartPainter oldDelegate) =>
      oldDelegate.serie != serie;
}