import 'package:flutter/material.dart';
import 'package:pole_price/models/draft_aprova_model.dart';
import 'package:pole_price/service/draft_pricing_service.dart';
import 'package:pole_price/widgets/sidebar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AprovacoesScreen extends StatefulWidget {
  final String? draftIdInicial;

  const AprovacoesScreen({super.key, this.draftIdInicial});

  @override
  State<AprovacoesScreen> createState() => _AprovacoesScreenState();
}

class _AprovacoesScreenState extends State<AprovacoesScreen> {
  static const _laranja = Color(0xFFFF6B00);

  late final DraftPricingService _draftService;

  bool _loadingDrafts = true;
  bool _loadingDetalhes = false;
  bool _aprovando = false;

  List<DraftAprovacao> _rascunhosPendentes = [];
  DraftAprovacao? _rascunhoSelecionado;

  List<Map<String, dynamic>> _materiais = [];
  String _detalheCabecalho = '';

  String _filtroTab = 'todos';
  String _busca = '';
  final Set<String> _listasExpandidas = {};

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _draftService = DraftPricingService(client);
    _buscarRascunhosPendentes();
  }

  Future<void> _buscarRascunhosPendentes() async {
    setState(() => _loadingDrafts = true);
    try {
      final response = await Supabase.instance.client
          .from('price_drafts')
          .select(
            'id, status, created_at, master_list_id, price_lists!master_list_id(description)',
          )
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final lista = (response as List)
          .map((json) => DraftAprovacao.fromJson(json))
          .toList();

      setState(() => _rascunhosPendentes = lista);

      final idInicial = widget.draftIdInicial;
      if (idInicial != null && mounted) {
        final draft = lista.cast<DraftAprovacao?>().firstWhere(
              (d) => d?.id == idInicial,
              orElse: () => null,
            );
        if (draft != null) {
          await _carregarDetalhesRascunho(draft);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao buscar rascunhos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _loadingDrafts = false);
    }
  }

  Future<void> _carregarDetalhesRascunho(DraftAprovacao draft) async {
    setState(() {
      _loadingDetalhes = true;
      _rascunhoSelecionado = draft;
      _materiais.clear();
      _detalheCabecalho = '';
      _listasExpandidas.clear();
      _filtroTab = 'todos';
      _busca = '';
    });

    try {
      final preview = await _draftService.buildPreview(draft.id);
      setState(() {
        _materiais = preview.materiais.map((m) => m.toRowMap()).toList();
        _detalheCabecalho = preview.resumo;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar detalhes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _loadingDetalhes = false);
    }
  }

  Future<void> _aprovarRascunho() async {
    if (_rascunhoSelecionado == null) return;
    setState(() => _aprovando = true);

    try {
      final draftId = _rascunhoSelecionado!.id;
      final qtdAtualizados = await _draftService.applyDraft(draftId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$qtdAtualizados preço(s) publicados em materials (Supabase).',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
        _limparSelecao();
        _buscarRascunhosPendentes();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao aprovar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _aprovando = false);
    }
  }

  Future<void> _rejeitarRascunho() async {
    if (_rascunhoSelecionado == null) return;
    setState(() => _aprovando = true);
    try {
      await Supabase.instance.client
          .from('price_drafts')
          .update({'status': 'rejected'})
          .eq('id', _rascunhoSelecionado!.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rascunho rejeitado.'),
            backgroundColor: Colors.orange,
          ),
        );
        _limparSelecao();
        _buscarRascunhosPendentes();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao rejeitar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _aprovando = false);
    }
  }

  void _limparSelecao() {
    setState(() {
      _rascunhoSelecionado = null;
      _materiais.clear();
      _detalheCabecalho = '';
      _listasExpandidas.clear();
    });
  }

  void _toggleLista(String chave) {
    setState(() {
      if (_listasExpandidas.contains(chave)) {
        _listasExpandidas.remove(chave);
      } else {
        _listasExpandidas.add(chave);
      }
    });
  }

  List<Map<String, dynamic>> _materiaisFiltrados(List<Map<String, dynamic>> grupo) {
    return grupo.where((item) {
      final status = _statusLabel(item);
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

  Map<String, List<Map<String, dynamic>>> _agruparPorLista() {
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final mat in _materiais) {
      final chave = mat['lista_id'] as String;
      grupos.putIfAbsent(chave, () => []).add(mat);
    }
    return grupos;
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _gruposOrdenados() {
    final grupos = _agruparPorLista();
    final entries = grupos.entries.toList()
      ..sort((a, b) {
        final aMae = a.value.first['tipo_lista'] == 'mae';
        final bMae = b.value.first['tipo_lista'] == 'mae';
        if (aMae && !bMae) return -1;
        if (!aMae && bMae) return 1;
        return a.value.first['lista_nome']
            .toString()
            .compareTo(b.value.first['lista_nome'].toString());
      });
    return entries;
  }

  _KpiData _calcularKpis() {
    final total = _materiais.length;
    final alterados =
        _materiais.where((m) => m['foi_editado'] == true).length;
    final excecoes = _materiais
        .where((m) => _statusLabel(m) == 'Exceção manual')
        .length;

    return _KpiData(
      total: total,
      alterados: alterados,
      semAlteracao: total - alterados,
      excecoes: excecoes,
    );
  }

  int _countListasFilhas() {
    return _agruparPorLista().values
        .where((g) => g.first['tipo_lista'] == 'filha')
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final kpis = _materiais.isNotEmpty ? _calcularKpis() : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Row(
        children: [
          const Sidebar(paginaAtiva: 'Aprovações'),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _painelRascunhos(),
                Expanded(
                  child: _rascunhoSelecionado == null
                      ? _estadoVazio()
                      : _loadingDetalhes
                          ? const Center(child: CircularProgressIndicator())
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _cabecalho(),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      24, 12, 24, 0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (kpis != null) _kpiCards(kpis),
                                      if (_detalheCabecalho.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        _regrasAplicadas(),
                                      ],
                                      const SizedBox(height: 10),
                                      _filtrosEBusca(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        24, 0, 24, 16),
                                    child: _tabelaMateriais(),
                                  ),
                                ),
                              ],
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _painelRascunhos() {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rascunhos pendentes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_rascunhosPendentes.length} aguardando revisão',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loadingDrafts
                ? const Center(child: CircularProgressIndicator())
                : _rascunhosPendentes.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum rascunho pendente.',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _rascunhosPendentes.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade100),
                        itemBuilder: (context, i) {
                          final d = _rascunhosPendentes[i];
                          final selected = _rascunhoSelecionado?.id == d.id;
                          return _draftCard(d, selected);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _draftCard(DraftAprovacao d, bool selected) {
    return Material(
      color: selected ? _laranja.withOpacity(0.06) : Colors.transparent,
      child: InkWell(
        onTap: () => _carregarDetalhesRascunho(d),
        child: Container(
          decoration: BoxDecoration(
            border: selected
                ? Border(
                    left: BorderSide(color: _laranja, width: 3),
                  )
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.masterListName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: selected ? _laranja : Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      d.createdAtFormatado,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: selected ? _laranja : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _estadoVazio() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fact_check_outlined,
              size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Selecione um rascunho para revisar',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Audite materiais, diferenças e regras antes de aprovar.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho() {
    final d = _rascunhoSelecionado!;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Aprovações',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
              Text(
                d.masterListName,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aprovação de preços: ${d.masterListName}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Criado em ${d.createdAtFormatado}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              _badge('Pendente', _laranja.withOpacity(0.1), _laranja),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _aprovando ? null : _rejeitarRascunho,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                ),
                child: const Text('Rejeitar'),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _aprovando ? null : _aprovarRascunho,
                icon: _aprovando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check, size: 18),
                label: Text(_aprovando ? 'Aprovando...' : 'Aprovar e publicar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _laranja,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiCards(_KpiData k) {
    final pctAlterados =
        k.total > 0 ? (k.alterados / k.total * 100) : 0.0;
    final pctSemAlt =
        k.total > 0 ? (k.semAlteracao / k.total * 100) : 0.0;

    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            icon: Icons.inventory_2_outlined,
            label: 'Total',
            valor: '${k.total}',
            sub: 'materiais',
            cor: Colors.blue.shade600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiCard(
            icon: Icons.edit_outlined,
            label: 'Alterados',
            valor: '${k.alterados}',
            sub: '${pctAlterados.toStringAsFixed(1)}%',
            cor: _laranja,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiCard(
            icon: Icons.remove_circle_outline,
            label: 'Sem alteração',
            valor: '${k.semAlteracao}',
            sub: '${pctSemAlt.toStringAsFixed(1)}%',
            cor: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiCard(
            icon: Icons.rule_outlined,
            label: 'Exceções',
            valor: '${k.excecoes}',
            sub: '${_countListasFilhas()} listas filhas',
            cor: Colors.purple.shade600,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required String label,
    required String valor,
    required String sub,
    required Color cor,
  }) {
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
          Row(
            children: [
              Icon(icon, size: 16, color: cor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
          Text(sub, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _regrasAplicadas() {
    final linhas = _detalheCabecalho.split('\n').where((l) => l.isNotEmpty);
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
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              const Text(
                'Regras aplicadas',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...linhas.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                l,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtrosEBusca() {
    final tabs = [
      ('todos', 'Todos', _materiais.length),
      (
        'alterados',
        'Alterados',
        _materiais.where((m) => m['foi_editado'] == true).length
      ),
      (
        'sem_alteracao',
        'Sem alteração',
        _materiais.where((m) => m['foi_editado'] != true).length
      ),
      (
        'excecoes',
        'Exceções',
        _materiais.where((m) => _statusLabel(m) == 'Exceção manual').length
      ),
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
            final active = _filtroTab == t.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text('${t.$2} (${t.$3})'),
                selected: active,
                onSelected: (_) => setState(() => _filtroTab = t.$1),
                selectedColor: _laranja.withOpacity(0.12),
                checkmarkColor: _laranja,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? _laranja : Colors.grey.shade700,
                ),
                side: BorderSide(
                  color: active ? _laranja.withOpacity(0.4) : Colors.grey.shade300,
                ),
                showCheckmark: false,
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
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade400),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
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
              onChanged: (v) => setState(() => _busca = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabelaMateriais() {
    final grupos = _gruposOrdenados();

    if (grupos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Center(
          child: Text(
            'Nenhum material encontrado.',
            style: TextStyle(color: Colors.grey.shade500),
          ),
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
          _tableHeader(),
          ...grupos.map((entry) {
            final chave = entry.key;
            final grupo = entry.value;
            final filtrados = _materiaisFiltrados(grupo);
            if (filtrados.isEmpty && _busca.isNotEmpty) {
              return const SizedBox.shrink();
            }
            if (filtrados.isEmpty &&
                _filtroTab != 'todos' &&
                _filtroTab != 'sem_alteracao') {
              return const SizedBox.shrink();
            }
            return _grupoLista(
              chave: chave,
              grupo: grupo,
              filtrados: filtrados,
            );
          }),
        ],
      ),
    );
  }

  Widget _grupoLista({
    required String chave,
    required List<Map<String, dynamic>> grupo,
    required List<Map<String, dynamic>> filtrados,
  }) {
    final meta = grupo.first;
    final tipoLista = meta['tipo_lista'] as String;
    final nomeLista = meta['lista_nome'] as String;
    final expandido = _listasExpandidas.contains(chave);
    final alteradosGrupo =
        grupo.where((m) => m['foi_editado'] == true).length;
    final corTipo = tipoLista == 'mae' ? _laranja : Colors.blue.shade700;

    return Column(
      children: [
        Material(
          color: expandido
              ? corTipo.withOpacity(0.04)
              : Colors.grey.shade50,
          child: InkWell(
            onTap: () => _toggleLista(chave),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    expandido
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 20,
                    color: corTipo,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    tipoLista == 'mae'
                        ? Icons.table_chart_outlined
                        : Icons.account_tree_outlined,
                    size: 16,
                    color: corTipo,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tipoLista == 'mae' ? 'Lista mãe' : 'Lista filha',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: corTipo,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nomeLista,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      '$alteradosGrupo/${grupo.length} alterados',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
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
              child: Text(
                'Nenhum material neste filtro.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            )
          else
            ...filtrados.map(_materialDataRow),
        ],
        Divider(height: 1, color: Colors.grey.shade100),
      ],
    );
  }

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.grey.shade50,
      child: Row(
        children: [
          _th('Código', flex: 2),
          _th('Material', flex: 5),
          _th('Lista', flex: 3),
          _th('Preço atual', flex: 2, align: TextAlign.right),
          _th('Preço proposto', flex: 2, align: TextAlign.right),
          _th('Dif. R\$', flex: 2, align: TextAlign.right),
          _th('Dif. %', flex: 2, align: TextAlign.right),
          _th('Status', flex: 3, align: TextAlign.center),
        ],
      ),
    );
  }

  Widget _materialDataRow(Map<String, dynamic> item) {
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
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _td(item['product_id'].toString(), flex: 2,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey.shade700)),
          _td(item['description'].toString(), flex: 5,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          _td(item['lista_nome'].toString(), flex: 3,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          _td(_fmtMoeda(antigo), flex: 2, align: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: alterado ? Colors.grey.shade500 : Colors.grey.shade800,
                decoration:
                    alterado ? TextDecoration.lineThrough : null,
              )),
          _td(_fmtMoeda(novo), flex: 2, align: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: alterado ? FontWeight.bold : FontWeight.normal,
                color: alterado ? Colors.grey.shade900 : Colors.grey.shade700,
              )),
          _td(
            '${dif >= 0 ? '+' : ''}${_fmtMoeda(dif)}',
            flex: 2,
            align: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: difColor,
            ),
          ),
          _td(
            '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
            flex: 2,
            align: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: difColor,
            ),
          ),
          Expanded(
            flex: 3,
            child: Center(child: _statusBadge(status)),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final (bg, fg) = switch (status) {
      'Alterado' => (Colors.green.shade50, Colors.green.shade700),
      'Exceção manual' => (_laranja.withOpacity(0.12), _laranja),
      _ => (Colors.grey.shade100, Colors.grey.shade600),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Widget _th(String label, {required int flex, TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _td(
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
        style: style ?? const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }

  static String _statusLabel(Map<String, dynamic> item) {
    if (item['foi_editado'] != true) return 'Sem alteração';
    final origem = item['origem']?.toString() ?? '';
    if (origem.startsWith('Reajuste')) return 'Exceção manual';
    return 'Alterado';
  }

  static String _fmtMoeda(double v) {
    final abs = v.abs().toStringAsFixed(2).replaceAll('.', ',');
    final prefix = v < 0 ? '-R\$ ' : 'R\$ ';
    return '$prefix$abs';
  }
}

class _KpiData {
  final int total;
  final int alterados;
  final int semAlteracao;
  final int excecoes;

  _KpiData({
    required this.total,
    required this.alterados,
    required this.semAlteracao,
    required this.excecoes,
  });
}

extension _DraftFormat on DraftAprovacao {
  String get createdAtFormatado {
    if (createdAt.length >= 10) {
      final parts = createdAt.substring(0, 10).split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
    }
    return createdAt;
  }
}
