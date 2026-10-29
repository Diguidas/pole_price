// lib/screens/relatorio_base_preco_screen.dart
//
// Relatório "Base de Preço" — grade no estilo do relatório SAP ZSDR0125
// (tabela ZSDT141): por material/lista, mostra vigência e os limites/valores
// de preço praticados no sistema (PPV MAX, PPV MIN, PPC FLAT, PPV PROMO,
// PPC PROMO), lidos dos rascunhos (price_draft_items) já salvos/aprovados —
// os mesmos campos que a tela de Preços grava (digitados ou calculados
// automaticamente pelas políticas de margem).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pole_price/service/pricing_policy_service.dart';
import 'package:pole_price/widgets/app_shell.dart';
import 'package:pole_price/widgets/lista_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modelo de linha da grade
// ─────────────────────────────────────────────────────────────────────────────

class _LinhaBasePreco {
  final String pltyp;
  final String listaNome;
  final String matnr;
  final String descricao;
  final String? datab;
  final String? datbi;
  final String draftStatus;
  final DateTime? dataReferencia;

  final double? ppvMax; // gkwrt
  final double? ppvMin; // mxwrt
  final double? ppcFlat; // ppc_novo
  final double? ppcPromo; // ppc_oferta
  final double? ppvPromo; // calculado: ppc_oferta * (1 - margem_oferta_efetiva)

  const _LinhaBasePreco({
    required this.pltyp,
    required this.listaNome,
    required this.matnr,
    required this.descricao,
    required this.datab,
    required this.datbi,
    required this.draftStatus,
    required this.dataReferencia,
    this.ppvMax,
    this.ppvMin,
    this.ppcFlat,
    this.ppcPromo,
    this.ppvPromo,
  });

  String get vigenciaFmt {
    String fmt(String? s) {
      if (s == null || s.length < 8) return '?';
      if (s == '99991231') return 'aberta';
      return '${s.substring(6, 8)}/${s.substring(4, 6)}/${s.substring(0, 4)}';
    }

    return '${fmt(datab)} → ${fmt(datbi)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tela
// ─────────────────────────────────────────────────────────────────────────────

class RelatorioBasePrecoScreen extends StatefulWidget {
  const RelatorioBasePrecoScreen({super.key});

  @override
  State<RelatorioBasePrecoScreen> createState() =>
      _RelatorioBasePrecoScreenState();
}

class _RelatorioBasePrecoScreenState extends State<RelatorioBasePrecoScreen> {
  static const _laranja = Color(0xFFE8793A);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _slate100 = Color(0xFFF1F5F9);
  static const _bgSuave = Color(0xFFF8FAFC);
  static const _verde = Color(0xFF10B981);
  static const _azul = Color(0xFF0EA5E9);

  final _supabase = Supabase.instance.client;
  late final _policyService = PricingPolicyService(_supabase);

  ListaRef? _lista;
  String _busca = '';

  // Ciclos (rascunhos aprovados) disponíveis para a lista selecionada —
  // mesma granularidade da tela de Histórico: um relatório por draft_id.
  List<Map<String, dynamic>> _ciclos = [];
  String? _cicloId;
  bool _loadingCiclos = false;

  // Filtro de vigência — compara contra datab (início) e/ou datbi (fim) de
  // cada linha, no formato SAP (YYYYMMDD), que ordena lexicograficamente
  // igual a uma comparação numérica.
  DateFilter? _vigDe;
  DateFilter? _vigAte;

  bool _loading = false;
  String? _erro;
  List<_LinhaBasePreco> _linhas = [];

  String _formatSapDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}'
      '${dt.month.toString().padLeft(2, '0')}'
      '${dt.day.toString().padLeft(2, '0')}';

  bool _cumpreFiltro(String? valor, DateFilter? filtro) {
    if (filtro == null) return true;
    if (valor == null || valor.length != 8) return false;
    final alvo = _formatSapDate(filtro.date);
    return switch (filtro.op) {
      DateOp.gte => valor.compareTo(alvo) >= 0,
      DateOp.lte => valor.compareTo(alvo) <= 0,
      DateOp.eq => valor == alvo,
      DateOp.neq => valor != alvo,
    };
  }

  List<_LinhaBasePreco> get _linhasFiltradas {
    var lista = _linhas;
    if (_vigDe != null) {
      lista = lista.where((l) => _cumpreFiltro(l.datab, _vigDe)).toList();
    }
    if (_vigAte != null) {
      lista = lista.where((l) => _cumpreFiltro(l.datbi, _vigAte)).toList();
    }
    if (_busca.trim().isNotEmpty) {
      final b = _busca.toLowerCase();
      lista = lista
          .where(
            (l) =>
                l.matnr.toLowerCase().contains(b) ||
                l.descricao.toLowerCase().contains(b),
          )
          .toList();
    }
    return lista;
  }

  String _opLabel(DateOp op) => switch (op) {
    DateOp.gte => '>=',
    DateOp.lte => '<=',
    DateOp.eq => '=',
    DateOp.neq => '<>',
  };

  String _exibirData(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  Future<void> _pickVigenciaDe() async {
    final result = await showDialog<DateFilter>(
      context: context,
      builder: (_) =>
          DateFilterDialog(initial: _vigDe, label: 'Vigência início (datab)'),
    );
    if (result == null) return;
    setState(() => _vigDe = result);
  }

  Future<void> _pickVigenciaAte() async {
    final result = await showDialog<DateFilter>(
      context: context,
      builder: (_) =>
          DateFilterDialog(initial: _vigAte, label: 'Vigência fim (datbi)'),
    );
    if (result == null) return;
    setState(() => _vigAte = result);
  }

  bool get _podeBuscar => _lista != null && _cicloId != null;

  String _fmtDataHora(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '—';
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$d/$mo/${dt.year} $h:$mi';
  }

  Future<void> _abrirListaPicker() async {
    final ref = await showListaPicker(context);
    if (ref == null) return;
    setState(() {
      _lista = ref;
      _linhas = [];
      _erro = null;
      _ciclos = [];
      _cicloId = null;
    });
    await _carregarCiclos();
  }

  /// Carrega os rascunhos aprovados desta lista (mãe) — cada um é um ciclo
  /// de preço já efetivado no SAP, igual às entradas da tela de Histórico.
  Future<void> _carregarCiclos() async {
    if (_lista == null) return;
    setState(() => _loadingCiclos = true);
    try {
      final res = await _supabase
          .from('price_drafts')
          .select('id, reviewed_at, vigencia_datab, vigencia_datbi')
          .eq('master_list_id', _lista!.pltyp)
          .eq('status', 'approved')
          .order('reviewed_at', ascending: false);
      final ciclos = (res as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _ciclos = ciclos;
        _cicloId = ciclos.isNotEmpty ? ciclos.first['id'].toString() : null;
        _loadingCiclos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar ciclos aprovados: $e';
        _loadingCiclos = false;
      });
    }
  }

  /// Lê os itens do rascunho (draft) selecionado — a MESMA granularidade
  /// usada pela tela de Histórico (um relatório por ciclo aprovado), em vez
  /// de agregar por ppc_historico (que só grava material com PPC digitado
  /// manualmente e por isso não bate com o total de itens do draft).
  Future<void> _consultar() async {
    if (_lista == null || _cicloId == null) return;
    setState(() {
      _loading = true;
      _erro = null;
      _linhas = [];
    });

    try {
      double? toD(dynamic v) =>
          v == null ? null : double.tryParse(v.toString());

      // 1. Política (margem oferta) da lista, para calcular PPV PROMO.
      final politica = await _policyService.getPolicyForLista(_lista!.pltyp);
      final margemOfertaPolitica = politica?.margemOferta;

      // 2. Todos os itens do ciclo (draft) selecionado — igual ao que a
      //    tela de Histórico usa como base para montar as linhas.
      final itensRes = await _supabase
          .from('price_draft_items')
          .select(
            'product_id, old_price, new_price, datab, datbi, mxwrt, gkwrt, '
            'ppc_novo, ppc_oferta, margem_oferta_override',
          )
          .eq('draft_id', _cicloId!);
      final itens = (itensRes as List).cast<Map<String, dynamic>>();

      if (itens.isEmpty) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      // 3. Descrições dos materiais.
      final codigos = itens
          .map((i) => i['product_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final prodRes = await _supabase
          .from('products')
          .select('code, name')
          .inFilter('code', codigos);
      final descMap = {
        for (final p in prodRes as List)
          p['code'].toString(): p['name']?.toString() ?? '',
      };

      // 4. Monta as linhas.
      final linhas = itens.map((item) {
        final pid = item['product_id']?.toString() ?? '';

        final ppcPromo = toD(item['ppc_oferta']);
        final margemOfertaEfetiva =
            toD(item['margem_oferta_override']) ?? margemOfertaPolitica;
        final ppvPromo = (ppcPromo != null && margemOfertaEfetiva != null)
            ? ppcPromo * (1 - margemOfertaEfetiva)
            : null;

        return _LinhaBasePreco(
          pltyp: _lista!.pltyp,
          listaNome: _lista!.ptext,
          matnr: pid,
          descricao: descMap[pid] ?? pid,
          datab: item['datab']?.toString(),
          datbi: item['datbi']?.toString(),
          draftStatus: 'approved',
          dataReferencia: null,
          ppvMax: toD(item['gkwrt']),
          ppvMin: toD(item['mxwrt']),
          ppcFlat: toD(item['ppc_novo']),
          ppcPromo: ppcPromo,
          ppvPromo: ppvPromo,
        );
      }).toList()
        ..sort((a, b) => a.matnr.compareTo(b.matnr));

      if (!mounted) return;
      setState(() {
        _linhas = linhas;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao consultar base de preço: $e';
        _loading = false;
      });
    }
  }

  String _statusLabel(String s) => switch (s) {
    'approved' => 'Aprovado',
    'pending' => 'Pendente',
    'draft' => 'Rascunho',
    _ => s.isEmpty ? '—' : s,
  };

  Color _statusCor(String s) => switch (s) {
    'approved' => _verde,
    'pending' => const Color(0xFFF59E0B),
    'draft' => _slate600,
    _ => _slate600,
  };

  String _fmtMoeda(double? v) => v == null ? '—' : v.toStringAsFixed(2);

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgSuave,
      body: Column(
        children: [
          _topBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _painelFiltros(),
                  const SizedBox(height: 16),
                  Expanded(child: _corpo()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() => Container(
    height: 72,
    padding: const EdgeInsets.symmetric(horizontal: 32),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: _slate100)),
      boxShadow: [BoxShadow(color: Color(0x06000000), blurRadius: 12)],
    ),
    child: const Row(
      children: [
        Icon(Icons.grid_on_rounded, color: _laranja, size: 24),
        SizedBox(width: 14),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Relatório Base de Preço',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _slate900,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              'Por ciclo aprovado (mesma base do Histórico) · PPV MAX · PPV MIN · PPC FLAT · PPV PROMO · PPC PROMO',
              style: TextStyle(
                fontSize: 12,
                color: _slate600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _painelFiltros() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _slate200),
      ),
      child: Row(
        children: [
          Flexible(
            flex: 3,
            child: GestureDetector(
              onTap: _abrirListaPicker,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _lista != null
                      ? _laranja.withOpacity(0.06)
                      : _bgSuave,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _lista != null ? _laranja : _slate200,
                    width: _lista != null ? 1.6 : 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.list_alt_rounded,
                      size: 15,
                      color: _lista != null ? _laranja : _slate600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _lista != null
                            ? '${_lista!.pltyp} — ${_lista!.ptext}'
                            : 'Selecionar lista…',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _lista != null
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _lista != null ? _laranja : _slate600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_lista != null)
                      GestureDetector(
                        onTap: () => setState(() {
                          _lista = null;
                          _linhas = [];
                          _ciclos = [];
                          _cicloId = null;
                        }),
                        behavior: HitTestBehavior.opaque,
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: _laranja.withOpacity(0.6),
                        ),
                      )
                    else
                      const Icon(
                        Icons.expand_more_rounded,
                        size: 16,
                        color: _slate600,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 40,
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 260),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _bgSuave,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _slate200),
            ),
            child: _loadingCiclos
                ? const Center(
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _cicloId,
                      isDense: true,
                      isExpanded: true,
                      hint: const Text(
                        'Ciclo (rascunho aprovado)',
                        style: TextStyle(fontSize: 12, color: _slate600),
                      ),
                      icon: const Icon(
                        Icons.expand_more_rounded,
                        size: 16,
                        color: _slate600,
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _slate900,
                      ),
                      items: _ciclos
                          .map(
                            (c) => DropdownMenuItem(
                              value: c['id'].toString(),
                              child: Text(
                                'Efetivado em ${_fmtDataHora(c['reviewed_at']?.toString())}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _ciclos.isEmpty
                          ? null
                          : (v) => setState(() => _cicloId = v),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Flexible(
            flex: 3,
            child: SizedBox(
              height: 40,
              child: TextField(
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar material…',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: _slate600,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: _bgSuave,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _slate200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _laranja),
                  ),
                ),
                onChanged: (v) => setState(() => _busca = v),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _dateTile(
            rotulo: 'Vigência de',
            valor: _vigDe != null
                ? '${_opLabel(_vigDe!.op)} ${_exibirData(_vigDe!.date)}'
                : 'Qualquer',
            onTap: _pickVigenciaDe,
            onClear: _vigDe != null ? () => setState(() => _vigDe = null) : null,
          ),
          const SizedBox(width: 8),
          _dateTile(
            rotulo: 'Vigência até',
            valor: _vigAte != null
                ? '${_opLabel(_vigAte!.op)} ${_exibirData(_vigAte!.date)}'
                : 'Qualquer',
            onTap: _pickVigenciaAte,
            onClear: _vigAte != null
                ? () => setState(() => _vigAte = null)
                : null,
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: _podeBuscar && !_loading ? _consultar : null,
            icon: _loading
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.grid_on_rounded, size: 18),
            label: Text(_loading ? 'Consultando…' : 'Consultar'),
            style: FilledButton.styleFrom(
              backgroundColor: _laranja,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateTile({
    required String rotulo,
    required String valor,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _bgSuave,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _slate200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_rounded, size: 13, color: _laranja),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rotulo,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: _slate600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _slate900,
                ),
              ),
            ],
          ),
          if (onClear != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onClear,
              child: const Icon(
                Icons.close_rounded,
                size: 13,
                color: _slate600,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _corpo() {
    if (_erro != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C)),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  _erro!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _laranja),
            SizedBox(height: 16),
            Text(
              'Consultando base de preço…',
              style: TextStyle(
                fontSize: 14,
                color: _slate600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (_lista == null) {
      return _EstadoVazio(
        icon: Icons.grid_on_outlined,
        titulo: 'Nenhuma consulta realizada',
        subtitulo: 'Selecione uma lista e clique em Consultar.',
      );
    }

    if (!_loadingCiclos && _ciclos.isEmpty) {
      return const _EstadoVazio(
        icon: Icons.grid_on_outlined,
        titulo: 'Nenhum ciclo aprovado',
        subtitulo:
            'Essa lista ainda não tem nenhum rascunho aprovado (aplicado no SAP).',
      );
    }

    final linhas = _linhasFiltradas;
    if (linhas.isEmpty) {
      return const _EstadoVazio(
        icon: Icons.grid_on_outlined,
        titulo: 'Nenhum dado encontrado',
        subtitulo:
            'Não há PPV/PPC salvos para essa lista com o filtro escolhido.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _slate200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: _slate100,
            child: Row(
              children: [
                Text(
                  '${linhas.length} material${linhas.length == 1 ? '' : 'is'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _slate900,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _slate200),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Scrollbar(
                  notificationPredicate: (n) => n.depth == 1,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: MediaQuery.of(context).size.width - 96,
                      ),
                      child: DataTable(
                  headingRowHeight: 38,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 40,
                  headingRowColor: WidgetStateProperty.all(_slate100),
                  columnSpacing: 20,
                  horizontalMargin: 16,
                  columns: const [
                    DataColumn(label: _Th('Material')),
                    DataColumn(label: _Th('Descrição')),
                    DataColumn(label: _Th('Vigência')),
                    DataColumn(label: _Th('Status')),
                    DataColumn(label: _Th('PPV MAX'), numeric: true),
                    DataColumn(label: _Th('PPV MIN'), numeric: true),
                    DataColumn(label: _Th('PPC FLAT'), numeric: true),
                    DataColumn(label: _Th('PPV PROMO'), numeric: true),
                    DataColumn(label: _Th('PPC PROMO'), numeric: true),
                  ],
                  rows: linhas
                      .map(
                        (l) => DataRow(
                          cells: [
                            DataCell(
                              Text(
                                l.matnr,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _slate900,
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 220,
                                child: Text(
                                  l.descricao,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _slate900,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                l.vigenciaFmt,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _slate600,
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _statusCor(
                                    l.draftStatus,
                                  ).withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _statusLabel(l.draftStatus),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _statusCor(l.draftStatus),
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                _fmtMoeda(l.ppvMax),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            DataCell(
                              Text(
                                _fmtMoeda(l.ppvMin),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            DataCell(
                              Text(
                                _fmtMoeda(l.ppcFlat),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _azul,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                _fmtMoeda(l.ppvPromo),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            DataCell(
                              Text(
                                _fmtMoeda(l.ppcPromo),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _verde,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Th extends StatelessWidget {
  final String label;
  const _Th(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: Color(0xFF475569),
        letterSpacing: 0.2,
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String subtitulo;

  const _EstadoVazio({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 42, color: const Color(0xFFCBD5E1)),
          const SizedBox(height: 12),
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitulo,
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
