// relatorio_screen.dart
// Tela de relatório: seleciona lista de preço e visualiza histórico de mudanças
// de preço por material. Reconstrói o histórico a partir dos price_draft_items
// de drafts aprovados (reviewed_at = data da mudança efetiva).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pole_price/widgets/sidebar.dart';

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

// ─────────────────────────────────────────────────────────────────────────────
// Tela principal
// ─────────────────────────────────────────────────────────────────────────────
class RelatorioScreen extends StatefulWidget {
  const RelatorioScreen({super.key});

  @override
  State<RelatorioScreen> createState() => _RelatorioScreenState();
}

class _RelatorioScreenState extends State<RelatorioScreen> {
  static const _laranja = Color(0xFFFF6B00);
  final _supabase = Supabase.instance.client;

  // Listas disponíveis
  bool _loadingListas = true;
  List<Map<String, dynamic>> _listas = [];
  String? _listaSelecionadaId;
  String _listaSelecionadaNome = '';

  // Histórico carregado
  bool _loadingHistorico = false;
  List<_SerieHistorico> _series = [];
  DateTime? _dataMin;
  DateTime? _dataMax;

  // Seleção de materiais para o gráfico
  final Set<String> _materiaisSelecionados = {};
  String _buscaMaterial = '';

  // Agrupamento do gráfico: 'mes' ou 'dia'
  String _agrupamento = 'mes';

  // Tooltip do gráfico
  _PontoHistorico? _tooltipPonto;
  String? _tooltipProductId;
  Offset _tooltipOffset = Offset.zero;

  // Expansão das linhas da tabela de histórico
  final Set<String> _materiaisExpandidos = {};

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
        _listas = (res as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      _snack('Erro ao carregar listas: $e');
    } finally {
      setState(() => _loadingListas = false);
    }
  }

  Future<void> _carregarHistorico(String listaId) async {
    setState(() {
      _loadingHistorico = true;
      _series = [];
      _materiaisSelecionados.clear();
      _materiaisExpandidos.clear();
      _tooltipPonto = null;
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
        setState(() => _loadingHistorico = false);
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
        setState(() => _loadingHistorico = false);
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
      final series = porProduto.entries
          .map((e) {
            final pts = e.value..sort((a, b) => a.data.compareTo(b.data));
            return _SerieHistorico(
              productId: e.key,
              description: descricoes[e.key] ?? e.key,
              pontos: pts,
            );
          })
          .toList()
        ..sort((a, b) => a.description.compareTo(b.description));

      // Calcula range de datas global
      DateTime? dMin, dMax;
      for (final s in series) {
        for (final p in s.pontos) {
          if (dMin == null || p.data.isBefore(dMin)) dMin = p.data;
          if (dMax == null || p.data.isAfter(dMax)) dMax = p.data;
        }
      }

      setState(() {
        _series = series;
        _dataMin = dMin;
        _dataMax = dMax;
        // Seleciona até 5 materiais com mais mudanças por padrão
        final ordenados = [...series]
          ..sort((a, b) => b.pontos.length.compareTo(a.pontos.length));
        for (final s in ordenados.take(5)) {
          _materiaisSelecionados.add(s.productId);
        }
      });
    } catch (e) {
      _snack('Erro ao carregar histórico: $e');
    } finally {
      setState(() => _loadingHistorico = false);
    }
  }

  // ── Agrupamento por período ───────────────────────────────────────────────

  /// Agrupa os pontos de uma série pelo período selecionado (mês ou dia),
  /// retendo apenas o último preço registrado em cada período.
  /// No modo 'tudo', retorna todos os pontos sem agrupar (timestamp completo).
  List<_PontoHistorico> _agruparPontos(List<_PontoHistorico> pontos) {
    if (pontos.isEmpty) return [];

    // Modo "Tudo": sem agrupamento, usa timestamp real
    if (_agrupamento == 'tudo') {
      return [...pontos]..sort((a, b) => a.data.compareTo(b.data));
    }

    DateTime chave(_PontoHistorico p) {
      if (_agrupamento == 'mes') {
        return DateTime(p.data.year, p.data.month);
      }
      return DateTime(p.data.year, p.data.month, p.data.day);
    }

    final Map<DateTime, _PontoHistorico> porPeriodo = {};
    for (final p in pontos) {
      final k = chave(p);
      // Mantém o mais recente do período
      final existing = porPeriodo[k];
      if (existing == null || p.data.isAfter(existing.data)) {
        porPeriodo[k] = _PontoHistorico(
          data: k, // normaliza a data para início do período
          preco: p.preco,
          precoAnterior: p.precoAnterior,
          draftId: p.draftId,
        );
      }
    }

    return porPeriodo.values.toList()
      ..sort((a, b) => a.data.compareTo(b.data));
  }

  List<_SerieHistorico> get _seriesAgrupadas => _seriesNoGrafico
      .map((s) => _SerieHistorico(
            productId: s.productId,
            description: s.description,
            pontos: _agruparPontos(s.pontos),
          ))
      .toList();

  // ── KPIs globais ──────────────────────────────────────────────────────────

  double? get _mediaInicial {
    final selecionadas = _series
        .where((s) => _materiaisSelecionados.contains(s.productId))
        .toList();
    if (selecionadas.isEmpty) return null;
    return selecionadas.map((s) => s.precoInicial).reduce((a, b) => a + b) /
        selecionadas.length;
  }

  double? get _mediaFinal {
    final selecionadas = _series
        .where((s) => _materiaisSelecionados.contains(s.productId))
        .toList();
    if (selecionadas.isEmpty) return null;
    return selecionadas.map((s) => s.precoFinal).reduce((a, b) => a + b) /
        selecionadas.length;
  }

  double? get _variacaoMediaPct {
    final selecionadas = _series
        .where((s) => _materiaisSelecionados.contains(s.productId))
        .toList();
    if (selecionadas.isEmpty) return null;
    return selecionadas.map((s) => s.variacaoPct).reduce((a, b) => a + b) /
        selecionadas.length;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String _fmtData(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  String _fmtMes(DateTime dt) {
    const meses = [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
    ];
    return '${meses[dt.month - 1]}/${dt.year.toString().substring(2)}';
  }

  String _fmtHora(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${_fmtData(dt)} $h:$m';
  }

  String _fmtMoeda(double v) {
    return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  List<_SerieHistorico> get _seriesFiltradas {
    if (_buscaMaterial.isEmpty) return _series;
    final q = _buscaMaterial.toLowerCase();
    return _series
        .where((s) =>
            s.description.toLowerCase().contains(q) ||
            s.productId.toLowerCase().contains(q))
        .toList();
  }

  List<_SerieHistorico> get _seriesNoGrafico => _series
      .where((s) => _materiaisSelecionados.contains(s.productId))
      .toList();

  // ── Cores para séries ─────────────────────────────────────────────────────
  static const _cores = [
    Color(0xFFFF6B00),
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFF9333EA),
    Color(0xFFEA580C),
    Color(0xFF0891B2),
    Color(0xFFD97706),
    Color(0xFFDC2626),
    Color(0xFF4F46E5),
    Color(0xFF059669),
  ];

  Color _corPorIndex(int i) => _cores[i % _cores.length];

  Color _corPorProductId(String pid) {
    final idx = _seriesNoGrafico.indexWhere((s) => s.productId == pid);
    return idx >= 0 ? _corPorIndex(idx) : Colors.grey;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Row(
        children: [
          const Sidebar(paginaAtiva: 'relatorio'),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topbar(),
                Expanded(
                  child: _listaSelecionadaId == null
                      ? _estadoInicial()
                      : _loadingHistorico
                          ? const Center(child: CircularProgressIndicator())
                          : _corpo(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Topbar ────────────────────────────────────────────────────────────────
  Widget _topbar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          const Text('Relatório de preços',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(width: 24),
          _loadingListas
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: DropdownButtonFormField<String>(
                      value: _listaSelecionadaId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        hintText: 'Selecione uma lista de preço...',
                        hintStyle: TextStyle(
                            fontSize: 13, color: Colors.grey.shade400),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      items: _listas.map((l) {
                        return DropdownMenuItem<String>(
                          value: l['id'].toString(),
                          child: Text(
                            l['description']?.toString() ?? l['id'],
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final nome = _listas
                                .firstWhere((l) => l['id'] == v)['description']
                                ?.toString() ??
                            v;
                        setState(() {
                          _listaSelecionadaId = v;
                          _listaSelecionadaNome = nome;
                        });
                        _carregarHistorico(v);
                      },
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  // ── Estado inicial ────────────────────────────────────────────────────────
  Widget _estadoInicial() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Selecione uma lista de preço',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Text(
            'O gráfico mostrará a evolução de preços ao longo dos drafts aprovados.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // ── Corpo principal ───────────────────────────────────────────────────────
  Widget _corpo() {
    if (_series.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_toggle_off_rounded,
                size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Nenhum draft aprovado encontrado para "$_listaSelecionadaNome".',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'O histórico é construído a partir de rascunhos aprovados.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Painel lateral de seleção de materiais
        _painelMateriais(),

        // Conteúdo principal: KPIs + gráfico + tabela
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _kpiChips(),
              Expanded(flex: 3, child: _grafico()),
              const Divider(height: 1),
              Expanded(flex: 2, child: _tabelaHistorico()),
            ],
          ),
        ),
      ],
    );
  }

  // ── KPI Chips ─────────────────────────────────────────────────────────────
  Widget _kpiChips() {
    final ini = _mediaInicial;
    final fin = _mediaFinal;
    final pct = _variacaoMediaPct;

    Color corVariacao = Colors.grey.shade600;
    if (pct != null) {
      corVariacao = pct > 0
          ? Colors.green.shade700
          : pct < 0
              ? Colors.red.shade600
              : Colors.grey.shade600;
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: _kpiChip(
              label: 'Preço médio inicial',
              valor: ini != null ? _fmtMoeda(ini) : '—',
              icon: Icons.price_change_outlined,
              cor: Colors.blue.shade700,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: _kpiChip(
              label: 'Preço médio atual',
              valor: fin != null ? _fmtMoeda(fin) : '—',
              icon: Icons.sell_outlined,
              cor: _laranja,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: _kpiChip(
              label: 'Variação média',
              valor: pct != null
                  ? '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%'
                  : '—',
              icon: pct != null && pct >= 0
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              cor: corVariacao,
              destaque: true,
            ),
          ),
          const Spacer(),
          // Toggle de agrupamento
          Text('Agrupar por:',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(width: 8),
          _toggleBtn('Mês', _agrupamento == 'mes',
              () => setState(() => _agrupamento = 'mes')),
          const SizedBox(width: 4),
          _toggleBtn('Dia', _agrupamento == 'dia',
              () => setState(() => _agrupamento = 'dia')),
          const SizedBox(width: 4),
          _toggleBtn('Tudo', _agrupamento == 'tudo',
              () => setState(() => _agrupamento = 'tudo')),
        ],
      ),
    );
  }

  Widget _kpiChip({
    required String label,
    required String valor,
    required IconData icon,
    required Color cor,
    bool destaque = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: destaque ? cor.withOpacity(0.07) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: destaque ? cor.withOpacity(0.25) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: cor),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(valor,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: cor)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _laranja : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? _laranja : Colors.grey.shade300,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.grey.shade600)),
      ),
    );
  }

  // ── Painel de seleção de materiais ────────────────────────────────────────
  Widget _painelMateriais() {
    final filtrados = _seriesFiltradas;

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Materiais',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.grey.shade800)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() {
                        if (_materiaisSelecionados.length == _series.length) {
                          _materiaisSelecionados.clear();
                        } else {
                          _materiaisSelecionados
                              .addAll(_series.map((s) => s.productId));
                        }
                      }),
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: Text(
                        _materiaisSelecionados.length == _series.length
                            ? 'Desmarcar todos'
                            : 'Selecionar todos',
                        style: const TextStyle(fontSize: 11, color: _laranja),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar material...',
                      hintStyle: TextStyle(
                          fontSize: 12, color: Colors.grey.shade400),
                      prefixIcon: Icon(Icons.search,
                          size: 16, color: Colors.grey.shade400),
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) => setState(() => _buscaMaterial = v),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: filtrados.length,
              itemBuilder: (_, i) {
                final s = filtrados[i];
                final selected =
                    _materiaisSelecionados.contains(s.productId);
                final corIdx = _series.indexOf(s);
                final cor = _corPorIndex(corIdx);

                return InkWell(
                  onTap: () => setState(() {
                    selected
                        ? _materiaisSelecionados.remove(s.productId)
                        : _materiaisSelecionados.add(s.productId);
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? cor.withOpacity(0.06)
                          : Colors.transparent,
                      border: selected
                          ? Border(
                              left: BorderSide(color: cor, width: 3))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: selected ? cor : Colors.grey.shade300,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: selected
                                      ? Colors.grey.shade900
                                      : Colors.grey.shade700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${s.productId} · ${s.pontos.length} mudança(s)',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),
                        Checkbox(
                          value: selected,
                          onChanged: (_) => setState(() {
                            selected
                                ? _materiaisSelecionados.remove(s.productId)
                                : _materiaisSelecionados.add(s.productId);
                          }),
                          activeColor: cor,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
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
    );
  }

  // ── Gráfico de linhas ─────────────────────────────────────────────────────
  Widget _grafico() {
    final series = _seriesAgrupadas;

    if (series.isEmpty || series.every((s) => s.pontos.isEmpty)) {
      return Container(
        color: Colors.white,
        child: Center(
          child: Text(
            'Selecione ao menos um material para visualizar o gráfico.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ),
      );
    }

    // Range Y
    double yMin = double.infinity;
    double yMax = double.negativeInfinity;
    for (final s in series) {
      for (final p in s.pontos) {
        if (p.preco < yMin) yMin = p.preco;
        if (p.preco > yMax) yMax = p.preco;
      }
    }
    final rawPad = (yMax - yMin) * 0.15;
    final yPad = rawPad < 1.0 ? (yMax * 0.05).clamp(1.0, double.infinity) : rawPad;
    yMin = (yMin - yPad).clamp(0, double.infinity);
    yMax = yMax + yPad;

    // Range X
    DateTime? xMin, xMax;
    for (final s in series) {
      for (final p in s.pontos) {
        if (xMin == null || p.data.isBefore(xMin)) xMin = p.data;
        if (xMax == null || p.data.isAfter(xMax)) xMax = p.data;
      }
    }
    if (xMin == null || xMax == null) return const SizedBox.shrink();

    final span = xMax.difference(xMin).inMilliseconds;
    // Quando todos os pontos são do mesmo dia, span é zero.
    // Garante um padding mínimo de 1 dia para que xToPixel funcione.
    final minPad = 1000 * 60 * 60 * 24; // 1 dia em ms
    final pad = span > 0 ? (span * 0.15).round() : minPad;
    final xMinP = xMin.subtract(Duration(milliseconds: pad));
    final xMaxP = xMax.add(Duration(milliseconds: pad));
    final xSpan = xMaxP.difference(xMinP).inMilliseconds.toDouble();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Título + range de datas
          Row(
            children: [
              Text(
                'Evolução de preços — $_listaSelecionadaNome',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_dataMin != null && _dataMax != null)
                Text(
                  '${_fmtData(_dataMin!)} → ${_fmtData(_dataMax!)}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Legenda de cores
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (var i = 0; i < series.length; i++)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 14,
                        height: 3,
                        decoration: BoxDecoration(
                          color: _corPorIndex(i),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          series[i].description,
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade700),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Gráfico
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight - 20; // 20px reservado para labels do eixo X

                double xToPixel(DateTime dt) {
                  final ms =
                      dt.difference(xMinP).inMilliseconds.toDouble();
                  return (ms / xSpan) * w;
                }

                double yToPixel(double v) {
                  final ratio = (v - yMin) / (yMax - yMin);
                  return h - ratio * h;
                }

                return MouseRegion(
                  onHover: (event) {
                    final mx = event.localPosition.dx;
                    _PontoHistorico? nearest;
                    String? nearestPid;
                    double minDist = double.infinity;

                    for (final s in series) {
                      for (final p in s.pontos) {
                        final px = xToPixel(p.data);
                        final dist = (px - mx).abs();
                        if (dist < minDist) {
                          minDist = dist;
                          nearest = p;
                          nearestPid = s.productId;
                        }
                      }
                    }

                    if (minDist < 40) {
                      setState(() {
                        _tooltipPonto = nearest;
                        _tooltipProductId = nearestPid;
                        _tooltipOffset = event.localPosition;
                      });
                    } else {
                      setState(() => _tooltipPonto = null);
                    }
                  },
                  onExit: (_) => setState(() => _tooltipPonto = null),
                  child: Stack(
                    children: [
                      // Grid Y
                      CustomPaint(
                        size: Size(w, h),
                        painter: _GridPainter(
                          yMin: yMin,
                          yMax: yMax,
                          yLines: 5,
                          fmtY: _fmtMoeda,
                        ),
                      ),
                      // Labels X (datas)
                      CustomPaint(
                        size: Size(w, h),
                        painter: _XAxisPainter(
                          series: series,
                          xToPixel: xToPixel,
                          fmtX: _agrupamento == 'mes'
                              ? _fmtMes
                              : _agrupamento == 'tudo'
                                  ? _fmtHora
                                  : _fmtData,
                        ),
                      ),
                      // Linhas
                      for (var i = 0; i < series.length; i++)
                        CustomPaint(
                          size: Size(w, h),
                          painter: _LinePainter(
                            pontos: series[i].pontos,
                            cor: _corPorIndex(i),
                            xToPixel: xToPixel,
                            yToPixel: yToPixel,
                          ),
                        ),
                      // Tooltip
                      if (_tooltipPonto != null)
                        Positioned(
                          left: (_tooltipOffset.dx + 12).clamp(0, w - 180),
                          top: (_tooltipOffset.dy - 60).clamp(0, h - 80),
                          child: _TooltipBox(
                            ponto: _tooltipPonto!,
                            productId: _tooltipProductId,
                            series: series,
                            cor: _tooltipProductId != null
                                ? _corPorProductId(_tooltipProductId!)
                                : _laranja,
                            fmtData: _agrupamento == 'mes'
                                ? _fmtMes
                                : _agrupamento == 'tudo'
                                    ? _fmtHora
                                    : _fmtData,
                            fmtMoeda: _fmtMoeda,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Tabela de histórico por material ──────────────────────────────────────
  Widget _tabelaHistorico() {
    final seriesVisiveis = _seriesNoGrafico;

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabeçalho
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: Colors.grey.shade50,
            child: Row(
              children: [
                _th('', flex: 1), // ícone expandir
                _th('Material', flex: 5),
                _th('Preço inicial', flex: 2, align: TextAlign.right),
                _th('Preço atual', flex: 2, align: TextAlign.right),
                _th('Variação R\$', flex: 2, align: TextAlign.right),
                _th('Variação %', flex: 2, align: TextAlign.right),
                _th('Mudanças', flex: 2, align: TextAlign.center),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: seriesVisiveis.isEmpty
                ? Center(
                    child: Text(
                      'Selecione materiais no painel à esquerda.',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: seriesVisiveis.length,
                    itemBuilder: (_, i) {
                      final s = seriesVisiveis[i];
                      final cor = _corPorProductId(s.productId);
                      final expandido = _materiaisExpandidos
                          .contains(s.productId);
                      final dif = s.variacaoAbsoluta;
                      final pct = s.variacaoPct;
                      final difColor = dif > 0
                          ? Colors.green.shade700
                          : dif < 0
                              ? Colors.red.shade600
                              : Colors.grey.shade500;

                      return Column(
                        children: [
                          // Linha resumo (clicável)
                          InkWell(
                            onTap: () => setState(() {
                              expandido
                                  ? _materiaisExpandidos
                                      .remove(s.productId)
                                  : _materiaisExpandidos
                                      .add(s.productId);
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 11),
                              decoration: BoxDecoration(
                                color: expandido
                                    ? cor.withOpacity(0.04)
                                    : null,
                                border: expandido
                                    ? Border(
                                        left: BorderSide(
                                            color: cor, width: 3))
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  // Ícone expandir
                                  Expanded(
                                    flex: 1,
                                    child: Icon(
                                      expandido
                                          ? Icons.keyboard_arrow_down
                                          : Icons.keyboard_arrow_right,
                                      size: 16,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                  // Material
                                  Expanded(
                                    flex: 5,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: cor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(s.description,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500),
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              Text(s.productId,
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors
                                                          .grey.shade500,
                                                      fontFamily:
                                                          'monospace')),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Preço inicial
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      _fmtMoeda(s.precoInicial),
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600),
                                    ),
                                  ),
                                  // Preço atual
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      _fmtMoeda(s.precoFinal),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  // Variação R$
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '${dif >= 0 ? '+' : ''}${_fmtMoeda(dif)}',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: difColor),
                                    ),
                                  ),
                                  // Variação %
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: difColor),
                                    ),
                                  ),
                                  // Nº de mudanças
                                  Expanded(
                                    flex: 2,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: cor.withOpacity(0.10),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${s.pontos.length}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: cor),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Sublinhas da evolução (quando expandido)
                          if (expandido) ...[
                            Container(
                              color: Colors.grey.shade50,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 6),
                              child: Row(
                                children: [
                                  const Expanded(flex: 1, child: SizedBox()),
                                  _thSub('Data', flex: 3),
                                  _thSub('Preço anterior', flex: 2, align: TextAlign.right),
                                  _thSub('Novo preço', flex: 2, align: TextAlign.right),
                                  _thSub('Variação R\$', flex: 2, align: TextAlign.right),
                                  _thSub('Variação %', flex: 2, align: TextAlign.right),
                                  const Expanded(flex: 2, child: SizedBox()),
                                ],
                              ),
                            ),
                            for (var j = 0; j < s.pontos.length; j++) ...[
                              _linhaEvolucao(
                                  s.pontos[j],
                                  j > 0 ? s.pontos[j - 1].preco : null,
                                  cor),
                            ],
                            const Divider(height: 1, thickness: 1),
                          ] else
                            Divider(
                                height: 1, color: Colors.grey.shade100),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _linhaEvolucao(
      _PontoHistorico ponto, double? precoAnteriorFallback, Color cor) {
    // Usa o old_price salvo no draft; se não tiver, usa o ponto anterior da série
    final anterior = ponto.precoAnterior ?? precoAnteriorFallback;
    final dif = anterior != null ? ponto.preco - anterior : null;
    final pct = (anterior != null && anterior > 0 && dif != null)
        ? (dif / anterior) * 100
        : null;
    final difColor = dif == null
        ? Colors.grey.shade500
        : dif > 0
            ? Colors.green.shade700
            : dif < 0
                ? Colors.red.shade600
                : Colors.grey.shade500;

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: cor.withOpacity(0.3), width: 3),
          bottom: BorderSide(color: Colors.grey.shade100),
        ),
      ),
      child: Row(
        children: [
          const Expanded(flex: 1, child: SizedBox()),
          // Data
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(Icons.circle, size: 6, color: cor.withOpacity(0.5)),
                const SizedBox(width: 8),
                Text(
                  _agrupamento == 'mes'
                      ? _fmtMes(ponto.data)
                      : _agrupamento == 'tudo'
                          ? _fmtHora(ponto.data)
                          : _fmtData(ponto.data),
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          // Preço anterior
          Expanded(
            flex: 2,
            child: Text(
              anterior != null ? _fmtMoeda(anterior) : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  decoration: anterior != null
                      ? TextDecoration.lineThrough
                      : null),
            ),
          ),
          // Novo preço
          Expanded(
            flex: 2,
            child: Text(
              _fmtMoeda(ponto.preco),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          // Variação R$
          Expanded(
            flex: 2,
            child: Text(
              dif != null
                  ? '${dif >= 0 ? '+' : ''}${_fmtMoeda(dif)}'
                  : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: difColor),
            ),
          ),
          // Variação %
          Expanded(
            flex: 2,
            child: Text(
              pct != null
                  ? '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%'
                  : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: difColor),
            ),
          ),
          const Expanded(flex: 2, child: SizedBox()),
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
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600)),
    );
  }

  static Widget _thSub(String label,
      {required int flex, TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(label,
          textAlign: align,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainters
// ─────────────────────────────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  final double yMin, yMax;
  final int yLines;
  final String Function(double) fmtY;

  _GridPainter(
      {required this.yMin,
      required this.yMax,
      required this.yLines,
      required this.fmtY});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.grey.shade100
      ..strokeWidth = 1;
    final textStyle = TextStyle(
        fontSize: 10, color: Colors.grey.shade400, fontFamily: 'monospace');

    for (var i = 0; i <= yLines; i++) {
      final ratio = i / yLines;
      final y = size.height - ratio * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);

      final valor = yMin + (yMax - yMin) * ratio;
      final tp = TextPainter(
        text: TextSpan(text: fmtY(valor), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - 12));
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.yMin != yMin || old.yMax != yMax;
}

class _XAxisPainter extends CustomPainter {
  final List<_SerieHistorico> series;
  final double Function(DateTime) xToPixel;
  final String Function(DateTime) fmtX;

  _XAxisPainter({
    required this.series,
    required this.xToPixel,
    required this.fmtX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = TextStyle(
        fontSize: 9, color: Colors.grey.shade400, fontFamily: 'monospace');
    final tickPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;

    // Coleta datas únicas de todos os pontos
    final Set<DateTime> datas = {};
    for (final s in series) {
      for (final p in s.pontos) {
        datas.add(p.data);
      }
    }

    for (final dt in datas) {
      final x = xToPixel(dt);
      canvas.drawLine(
          Offset(x, 0), Offset(x, size.height), tickPaint);
      final tp = TextPainter(
        text: TextSpan(text: fmtX(dt), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - 14));
    }
  }

  @override
  bool shouldRepaint(_XAxisPainter old) => true;
}

class _LinePainter extends CustomPainter {
  final List<_PontoHistorico> pontos;
  final Color cor;
  final double Function(DateTime) xToPixel;
  final double Function(double) yToPixel;

  _LinePainter({
    required this.pontos,
    required this.cor,
    required this.xToPixel,
    required this.yToPixel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pontos.isEmpty) return;

    final linePaint = Paint()
      ..color = cor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final dotPaint = Paint()
      ..color = cor
      ..style = PaintingStyle.fill;

    final dotBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Se só tem 1 ponto, desenha uma linha horizontal tracejada + ponto central
    if (pontos.length == 1) {
      final p = pontos.first;
      final x = xToPixel(p.data);
      final y = yToPixel(p.preco);
      final dashedPaint = Paint()
        ..color = cor.withOpacity(0.35)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      // Linha tracejada horizontal
      const dashW = 6.0, gapW = 4.0;
      double dx = 0;
      while (dx < size.width) {
        canvas.drawLine(Offset(dx, y), Offset((dx + dashW).clamp(0, size.width), y), dashedPaint);
        dx += dashW + gapW;
      }
      canvas.drawCircle(Offset(x, y), 6, dotBorderPaint);
      canvas.drawCircle(Offset(x, y), 4, dotPaint);
      return;
    }

    final path = Path();
    for (var i = 0; i < pontos.length; i++) {
      final p = pontos[i];
      final x = xToPixel(p.data);
      final y = yToPixel(p.preco);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        // Linha em degrau para destacar mudanças pontuais
        final prevX = xToPixel(pontos[i - 1].data);
        path.lineTo(prevX + (x - prevX) * 0.5, yToPixel(pontos[i - 1].preco));
        path.lineTo(prevX + (x - prevX) * 0.5, y);
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    for (final p in pontos) {
      final x = xToPixel(p.data);
      final y = yToPixel(p.preco);
      canvas.drawCircle(Offset(x, y), 6, dotBorderPaint);
      canvas.drawCircle(Offset(x, y), 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tooltip
// ─────────────────────────────────────────────────────────────────────────────
class _TooltipBox extends StatelessWidget {
  final _PontoHistorico ponto;
  final String? productId;
  final List<_SerieHistorico> series;
  final Color cor;
  final String Function(DateTime) fmtData;
  final String Function(double) fmtMoeda;

  const _TooltipBox({
    required this.ponto,
    required this.productId,
    required this.series,
    required this.cor,
    required this.fmtData,
    required this.fmtMoeda,
  });

  @override
  Widget build(BuildContext context) {
    final serie = productId != null
        ? series.cast<_SerieHistorico?>().firstWhere(
            (s) => s?.productId == productId,
            orElse: () => null)
        : null;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (serie != null) ...[
            Text(serie.description,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cor),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
          ],
          Text(fmtData(ponto.data),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text(fmtMoeda(ponto.preco),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: cor)),
          if (ponto.precoAnterior != null) ...[
            const SizedBox(height: 2),
            Text(
              'Anterior: ${fmtMoeda(ponto.precoAnterior!)}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }
}