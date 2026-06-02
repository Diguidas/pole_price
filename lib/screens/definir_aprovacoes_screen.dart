// definir_aprovacoes_screen.dart
// Fatorado em widgets privados para manter o arquivo legível.
import 'package:flutter/material.dart';
import 'package:pole_price/controllers/permissao_controller.dart';
import 'package:pole_price/models/draft_aprova_model.dart';
import 'package:pole_price/service/draft_pricing_service.dart';
import 'package:pole_price/service/preco_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tela principal
// ─────────────────────────────────────────────────────────────────────────────
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
    _draftService = DraftPricingService(Supabase.instance.client);
    _buscarRascunhosPendentes();
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  Future<void> _buscarRascunhosPendentes() async {
    setState(() => _loadingDrafts = true);
    try {
      final response = await Supabase.instance.client
          .from('price_drafts')
          .select('id, status, created_at, master_list_id, created_by_email')
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final drafts = response as List;

      // Busca nomes das listas pelo pltyp
      final pltyps = drafts
          .map((d) => d['master_list_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      final Map<String, String> nomePorPltyp = {};
      if (pltyps.isNotEmpty) {
        final listasRes = await Supabase.instance.client
            .from('price_lists')
            .select('pltyp, ptext')
            .inFilter('pltyp', pltyps);
        for (final l in listasRes as List) {
          nomePorPltyp[l['pltyp'].toString()] = l['ptext']?.toString() ?? '';
        }
      }

      final lista = drafts.map((j) {
        final pltyp = j['master_list_id']?.toString();
        return DraftAprovacao.fromJson({
          ...j,
          'lista_nome': nomePorPltyp[pltyp] ?? pltyp ?? '',
        });
      }).toList();

      setState(() => _rascunhosPendentes = lista);

      final idInicial = widget.draftIdInicial;
      if (idInicial != null && mounted) {
        final draft = lista.cast<DraftAprovacao?>().firstWhere(
          (d) => d?.id == idInicial,
          orElse: () => null,
        );
        if (draft != null) await _carregarDetalhesRascunho(draft);
      }
    } catch (e) {
      _snack('Erro ao buscar rascunhos: $e', Colors.red);
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
      _snack('Erro ao carregar detalhes: $e', Colors.red);
    } finally {
      setState(() => _loadingDetalhes = false);
    }
  }

  Future<void> _aprovarRascunho() async {
    if (_rascunhoSelecionado == null) return;
    setState(() => _aprovando = true);
    try {
      final draftId = _rascunhoSelecionado!.id;
      final reviewerEmail =
          Supabase.instance.client.auth.currentUser?.email ?? 'desconhecido';

      // Envia ao SAP e salva no Supabase (applyDraft + pushToSap)
      final priceService = PriceService(Supabase.instance.client);
      await priceService.approveDraft(draftId);

      // Salva quem aprovou e quando
      await Supabase.instance.client
          .from('price_drafts')
          .update({
            'reviewed_by_email': reviewerEmail,
            'reviewed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', draftId);

      _snack('Preços publicados com sucesso no SAP e Supabase.', Colors.green);
      _limparSelecao();
      _buscarRascunhosPendentes();
    } catch (e) {
      _snack('Erro ao aprovar: $e', Colors.red);
    } finally {
      setState(() => _aprovando = false);
    }
  }

  Future<void> _rejeitarRascunho() async {
    if (_rascunhoSelecionado == null) return;
    setState(() => _aprovando = true);
    try {
      final reviewerEmail =
          Supabase.instance.client.auth.currentUser?.email ?? 'desconhecido';

      await Supabase.instance.client
          .from('price_drafts')
          .update({
            'status': 'rejected',
            'reviewed_by_email': reviewerEmail,
            'reviewed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _rascunhoSelecionado!.id);

      _snack('Rascunho rejeitado.', Colors.orange);
      _limparSelecao();
      _buscarRascunhosPendentes();
    } catch (e) {
      _snack('Erro ao rejeitar: $e', Colors.red);
    } finally {
      setState(() => _aprovando = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _snack(String msg, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: cor));
  }

  void _limparSelecao() => setState(() {
    _rascunhoSelecionado = null;
    _materiais.clear();
    _detalheCabecalho = '';
    _listasExpandidas.clear();
  });

  void _toggleLista(String chave) => setState(() {
    _listasExpandidas.contains(chave)
        ? _listasExpandidas.remove(chave)
        : _listasExpandidas.add(chave);
  });

  List<Map<String, dynamic>> _materiaisFiltrados(
    List<Map<String, dynamic>> grupo,
  ) {
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
      grupos.putIfAbsent(mat['lista_id'] as String, () => []).add(mat);
    }
    return grupos;
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _gruposOrdenados() {
    return _agruparPorLista().entries.toList()..sort((a, b) {
      final aMae = a.value.first['tipo_lista'] == 'mae';
      final bMae = b.value.first['tipo_lista'] == 'mae';
      if (aMae && !bMae) return -1;
      if (!aMae && bMae) return 1;
      return a.value.first['lista_nome'].toString().compareTo(
        b.value.first['lista_nome'].toString(),
      );
    });
  }

  _KpiData _calcularKpis() {
    final total = _materiais.length;
    final alterados = _materiais.where((m) => m['foi_editado'] == true).length;
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

  int _countListasFilhas() => _agruparPorLista().values
      .where((g) => g.first['tipo_lista'] == 'filha')
      .length;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final kpis = _materiais.isNotEmpty ? _calcularKpis() : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PainelRascunhos(
            loading: _loadingDrafts,
            rascunhos: _rascunhosPendentes,
            selecionado: _rascunhoSelecionado,
            onSelecionar: _carregarDetalhesRascunho,
          ),
          Expanded(
            child: _rascunhoSelecionado == null
                ? const _EstadoVazio()
                : _loadingDetalhes
                ? const Center(child: CircularProgressIndicator())
                : _PainelDetalhes(
                    draft: _rascunhoSelecionado!,
                    materiais: _materiais,
                    detalheCabecalho: _detalheCabecalho,
                    filtroTab: _filtroTab,
                    busca: _busca,
                    listasExpandidas: _listasExpandidas,
                    kpis: kpis,
                    aprovando: _aprovando,
                    podeAprovar: PermissaoController.instance.podeAprovar,
                    countListasFilhas: _countListasFilhas(),
                    gruposOrdenados: _gruposOrdenados(),
                    materiaisFiltrados: _materiaisFiltrados,
                    onAprovar: _aprovarRascunho,
                    onRejeitar: _rejeitarRascunho,
                    onToggleLista: _toggleLista,
                    onFiltroTab: (v) => setState(() => _filtroTab = v),
                    onBusca: (v) => setState(() => _busca = v),
                  ),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(Map<String, dynamic> item) {
    if (item['foi_editado'] != true) return 'Sem alteração';
    final origem = item['origem']?.toString() ?? '';
    if (origem.startsWith('Reajuste')) return 'Exceção manual';
    return 'Alterado';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painel esquerdo: lista de rascunhos
// ─────────────────────────────────────────────────────────────────────────────
class _PainelRascunhos extends StatelessWidget {
  final bool loading;
  final List<DraftAprovacao> rascunhos;
  final DraftAprovacao? selecionado;
  final void Function(DraftAprovacao) onSelecionar;

  const _PainelRascunhos({
    required this.loading,
    required this.rascunhos,
    required this.selecionado,
    required this.onSelecionar,
  });

  @override
  Widget build(BuildContext context) {
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
                  '${rascunhos.length} aguardando revisão',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : rascunhos.isEmpty
                ? Center(
                    child: Text(
                      'Nenhum rascunho pendente.',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: rascunhos.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey.shade100),
                    itemBuilder: (_, i) {
                      final d = rascunhos[i];
                      final selected = selecionado?.id == d.id;
                      return _DraftCard(
                        draft: d,
                        selected: selected,
                        onTap: () => onSelecionar(d),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card de rascunho individual
// ─────────────────────────────────────────────────────────────────────────────
class _DraftCard extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  final DraftAprovacao draft;
  final bool selected;
  final VoidCallback onTap;

  const _DraftCard({
    required this.draft,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _laranja.withOpacity(0.06) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: selected
                ? const Border(left: BorderSide(color: _laranja, width: 3))
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
                      draft.masterListName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: selected ? _laranja : Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Mostra quem criou (email)
                    if (draft.createdByEmail != null &&
                        draft.createdByEmail!.isNotEmpty)
                      Text(
                        draft.createdByEmail!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 2),
                    Text(
                      draft.createdAtFormatado,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Estado vazio (nenhum rascunho selecionado)
// ─────────────────────────────────────────────────────────────────────────────
class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.fact_check_outlined,
            size: 56,
            color: Colors.grey.shade300,
          ),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Painel direito: detalhes do rascunho selecionado
// ─────────────────────────────────────────────────────────────────────────────
class _PainelDetalhes extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);

  final DraftAprovacao draft;
  final List<Map<String, dynamic>> materiais;
  final String detalheCabecalho;
  final String filtroTab;
  final String busca;
  final Set<String> listasExpandidas;
  final _KpiData? kpis;
  final bool aprovando;
  final bool podeAprovar;
  final int countListasFilhas;
  final List<MapEntry<String, List<Map<String, dynamic>>>> gruposOrdenados;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)
  materiaisFiltrados;
  final VoidCallback onAprovar;
  final VoidCallback onRejeitar;
  final void Function(String) onToggleLista;
  final void Function(String) onFiltroTab;
  final void Function(String) onBusca;

  const _PainelDetalhes({
    required this.draft,
    required this.materiais,
    required this.detalheCabecalho,
    required this.filtroTab,
    required this.busca,
    required this.listasExpandidas,
    required this.kpis,
    required this.aprovando,
    required this.podeAprovar,
    required this.countListasFilhas,
    required this.gruposOrdenados,
    required this.materiaisFiltrados,
    required this.onAprovar,
    required this.onRejeitar,
    required this.onToggleLista,
    required this.onFiltroTab,
    required this.onBusca,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Cabecalho(
          draft: draft,
          aprovando: aprovando,
          podeAprovar: podeAprovar,
          onAprovar: onAprovar,
          onRejeitar: onRejeitar,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (kpis != null)
                _KpiCards(kpis: kpis!, countListasFilhas: countListasFilhas),
              if (detalheCabecalho.isNotEmpty) ...[
                const SizedBox(height: 10),
                _RegrasAplicadas(texto: detalheCabecalho),
              ],
              const SizedBox(height: 10),
              _FiltrosEBusca(
                materiais: materiais,
                filtroTab: filtroTab,
                busca: busca,
                onFiltroTab: onFiltroTab,
                onBusca: onBusca,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: _TabelaMateriais(
              gruposOrdenados: gruposOrdenados,
              listasExpandidas: listasExpandidas,
              busca: busca,
              filtroTab: filtroTab,
              materiaisFiltrados: materiaisFiltrados,
              onToggleLista: onToggleLista,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cabeçalho do painel de detalhes
// ─────────────────────────────────────────────────────────────────────────────
class _Cabecalho extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  final DraftAprovacao draft;
  final bool aprovando;
  final bool podeAprovar;
  final VoidCallback onAprovar;
  final VoidCallback onRejeitar;

  const _Cabecalho({
    required this.draft,
    required this.aprovando,
    required this.podeAprovar,
    required this.onAprovar,
    required this.onRejeitar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb
          Row(
            children: [
              Text(
                'Aprovações',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
              Text(
                draft.masterListName,
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
                      'Aprovação de preços: ${draft.masterListName}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Criado por + data
                    Wrap(
                      spacing: 16,
                      children: [
                        Text(
                          'Criado em ${draft.createdAtFormatado}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (draft.createdByEmail != null &&
                            draft.createdByEmail!.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 14,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                draft.createdByEmail!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _badge('Pendente', _laranja.withOpacity(0.1), _laranja),
              const SizedBox(width: 12),
              if (podeAprovar) ...[
                OutlinedButton(
                  onPressed: aprovando ? null : onRejeitar,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('Rejeitar'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: aprovando ? null : onAprovar,
                  icon: aprovando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text(aprovando ? 'Aprovando...' : 'Aprovar e publicar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _laranja,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                ),
              ] else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 15, color: Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Text(
                        'Aguardando aprovação de um responsável',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _badge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI cards
// ─────────────────────────────────────────────────────────────────────────────
class _KpiCards extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  final _KpiData kpis;
  final int countListasFilhas;

  const _KpiCards({required this.kpis, required this.countListasFilhas});

  @override
  Widget build(BuildContext context) {
    final pctAlt = kpis.total > 0 ? kpis.alterados / kpis.total * 100 : 0.0;
    final pctSem = kpis.total > 0 ? kpis.semAlteracao / kpis.total * 100 : 0.0;

    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            Icons.inventory_2_outlined,
            'Total',
            '${kpis.total}',
            'materiais',
            Colors.blue.shade600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiCard(
            Icons.edit_outlined,
            'Alterados',
            '${kpis.alterados}',
            '${pctAlt.toStringAsFixed(1)}%',
            _laranja,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiCard(
            Icons.remove_circle_outline,
            'Sem alteração',
            '${kpis.semAlteracao}',
            '${pctSem.toStringAsFixed(1)}%',
            Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiCard(
            Icons.rule_outlined,
            'Exceções',
            '${kpis.excecoes}',
            '$countListasFilhas listas filhas',
            Colors.purple.shade600,
          ),
        ),
      ],
    );
  }

  static Widget _kpiCard(
    IconData icon,
    String label,
    String valor,
    String sub,
    Color cor,
  ) {
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
          Text(
            sub,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Regras aplicadas
// ─────────────────────────────────────────────────────────────────────────────
class _RegrasAplicadas extends StatelessWidget {
  final String texto;
  const _RegrasAplicadas({required this.texto});

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
}

// ─────────────────────────────────────────────────────────────────────────────
// Filtros e busca
// ─────────────────────────────────────────────────────────────────────────────
class _FiltrosEBusca extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  final List<Map<String, dynamic>> materiais;
  final String filtroTab;
  final String busca;
  final void Function(String) onFiltroTab;
  final void Function(String) onBusca;

  const _FiltrosEBusca({
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
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? _laranja : Colors.grey.shade700,
                ),
                side: BorderSide(
                  color: active
                      ? _laranja.withOpacity(0.4)
                      : Colors.grey.shade300,
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
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
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
              onChanged: onBusca,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tabela de materiais
// ─────────────────────────────────────────────────────────────────────────────
class _TabelaMateriais extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  final List<MapEntry<String, List<Map<String, dynamic>>>> gruposOrdenados;
  final Set<String> listasExpandidas;
  final String busca;
  final String filtroTab;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)
  materiaisFiltrados;
  final void Function(String) onToggleLista;

  const _TabelaMateriais({
    required this.gruposOrdenados,
    required this.listasExpandidas,
    required this.busca,
    required this.filtroTab,
    required this.materiaisFiltrados,
    required this.onToggleLista,
  });

  static String _statusLabel(Map<String, dynamic> item) {
    if (item['foi_editado'] != true) return 'Sem alteração';
    final origem = item['origem']?.toString() ?? '';
    if (origem.startsWith('Reajuste')) return 'Exceção manual';
    return 'Alterado';
  }

  @override
  Widget build(BuildContext context) {
    if (gruposOrdenados.isEmpty) {
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
          ...gruposOrdenados.map((entry) {
            final chave = entry.key;
            final grupo = entry.value;
            final filtrados = materiaisFiltrados(grupo);
            if (filtrados.isEmpty && busca.isNotEmpty) {
              return const SizedBox.shrink();
            }
            if (filtrados.isEmpty &&
                filtroTab != 'todos' &&
                filtroTab != 'sem_alteracao') {
              return const SizedBox.shrink();
            }
            return _GrupoLista(
              chave: chave,
              grupo: grupo,
              filtrados: filtrados,
              expandido: listasExpandidas.contains(chave),
              onToggle: () => onToggleLista(chave),
            );
          }),
        ],
      ),
    );
  }

  static Widget _tableHeader() {
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
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grupo de lista (expansível)
// ─────────────────────────────────────────────────────────────────────────────
class _GrupoLista extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  final String chave;
  final List<Map<String, dynamic>> grupo;
  final List<Map<String, dynamic>> filtrados;
  final bool expandido;
  final VoidCallback onToggle;

  const _GrupoLista({
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
    final alteradosGrupo = grupo.where((m) => m['foi_editado'] == true).length;
    final corTipo = tipoLista == 'mae' ? _laranja : Colors.blue.shade700;

    return Column(
      children: [
        Material(
          color: expandido ? corTipo.withOpacity(0.04) : Colors.grey.shade50,
          child: InkWell(
            onTap: onToggle,
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
                      horizontal: 8,
                      vertical: 3,
                    ),
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
            ...filtrados.map((item) => _MaterialRow(item: item)),
        ],
        Divider(height: 1, color: Colors.grey.shade100),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Linha de material na tabela
// ─────────────────────────────────────────────────────────────────────────────
class _MaterialRow extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  final Map<String, dynamic> item;
  const _MaterialRow({required this.item});

  static String _statusLabel(Map<String, dynamic> item) {
    if (item['foi_editado'] != true) return 'Sem alteração';
    final origem = item['origem']?.toString() ?? '';
    if (origem.startsWith('Reajuste')) return 'Exceção manual';
    return 'Alterado';
  }

  static String _fmtMoeda(double v) {
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _td(
            item['product_id'].toString(),
            flex: 2,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
          _td(
            item['description'].toString(),
            flex: 5,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          _td(
            item['lista_nome'].toString(),
            flex: 3,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          _td(
            _fmtMoeda(antigo),
            flex: 2,
            align: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: alterado ? Colors.grey.shade500 : Colors.grey.shade800,
              decoration: alterado ? TextDecoration.lineThrough : null,
            ),
          ),
          _td(
            _fmtMoeda(novo),
            flex: 2,
            align: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: alterado ? FontWeight.bold : FontWeight.normal,
              color: alterado ? Colors.grey.shade900 : Colors.grey.shade700,
            ),
          ),
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
            child: Center(child: _StatusBadge(status: status)),
          ),
        ],
      ),
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
        style: style ?? const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
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
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data classes
// ─────────────────────────────────────────────────────────────────────────────
class _KpiData {
  final int total, alterados, semAlteracao, excecoes;
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
      if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    }
    return createdAt;
  }
}


