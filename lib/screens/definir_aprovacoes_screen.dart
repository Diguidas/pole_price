import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/draft_aprova_model.dart';
import '../widgets/sidebar.dart';

class AprovacoesScreen extends StatefulWidget {
  const AprovacoesScreen({super.key});

  @override
  State<AprovacoesScreen> createState() => _AprovacoesScreenState();
}

class _AprovacoesScreenState extends State<AprovacoesScreen> {
  final _supabase = Supabase.instance.client;

  bool _loadingDrafts = true;
  bool _loadingDetalhes = false;

  List<DraftAprovacao> _rascunhosPendentes = [];
  DraftAprovacao? _rascunhoSelecionado;

  List<dynamic> _itensAlterados = [];
  List<dynamic> _regrasExcecao = [];

  @override
  void initState() {
    super.initState();
    _buscarRascunhosPendentes();
  }

  Future<void> _buscarRascunhosPendentes() async {
    setState(() => _loadingDrafts = true);
    try {
      final response = await _supabase
          .from('price_drafts')
          .select('id, status, created_at, price_lists(description)')
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      setState(() {
        _rascunhosPendentes = (response as List)
            .map((d) => DraftAprovacao.fromJson(d))
            .toList();
        _loadingDrafts = false;
        _rascunhoSelecionado = null;
        _itensAlterados.clear();
        _regrasExcecao.clear();
      });
    } catch (e) {
      _mostrarSnackBar('Erro ao buscar rascunhos: $e', isError: true);
      setState(() => _loadingDrafts = false);
    }
  }

  Future<void> _carregarDetalhesDoRascunho(DraftAprovacao draft) async {
    setState(() {
      _rascunhoSelecionado = draft;
      _loadingDetalhes = true;
    });

    try {
      final itensRes = await _supabase
          .from('price_draft_items')
          .select('product_id, old_price, new_price, margin_pct')
          .eq('draft_id', draft.id);

      final excecoesRes = await _supabase
          .from('price_draft_exceptions')
          .select(
            'level, adjust_type, value, cluster_id, material_id, reference_desc, price_lists(description)',
          )
          .eq('draft_id', draft.id);

      setState(() {
        _itensAlterados = itensRes as List;
        _regrasExcecao = excecoesRes as List;
      });
    } catch (e) {
      _mostrarSnackBar('Erro ao carregar detalhes: $e', isError: true);
    } finally {
      setState(() => _loadingDetalhes = false);
    }
  }

  Future<void> _atualizarStatusRascunho(String novoStatus) async {
    if (_rascunhoSelecionado == null) return;

    setState(() => _loadingDetalhes = true);
    try {
      await _supabase
          .from('price_drafts')
          .update({'status': novoStatus})
          .eq('id', _rascunhoSelecionado!.id);

      _mostrarSnackBar(
        novoStatus == 'approved'
            ? 'Rascunho aprovado com sucesso!'
            : 'Rascunho rejeitado.',
        isError: novoStatus != 'approved',
      );

      _buscarRascunhosPendentes();
    } catch (e) {
      _mostrarSnackBar('Erro ao atualizar status: $e', isError: true);
      setState(() => _loadingDetalhes = false);
    }
  }

  void _mostrarSnackBar(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const corLaranja = Color(0xFFFF6B00);

    return Scaffold(
      body: Row(
        children: [
          // Sidebar com navegação — mesma estrutura da PrecoScreen
          const Sidebar(paginaAtiva: 'aprovacoes'),

          // Conteúdo principal
          Expanded(
            child: Column(
              children: [
                // Topbar consistente com o restante do app
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade100),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Painel de Aprovações',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Atualizar lista',
                        onPressed: _buscarRascunhosPendentes,
                      ),
                    ],
                  ),
                ),

                // Body dividido em dois painéis
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // PAINEL ESQUERDO: Lista de pendentes
                        Expanded(
                          flex: 2,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'Rascunhos Aguardando',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: _loadingDrafts
                                      ? const Center(
                                          child: CircularProgressIndicator(),
                                        )
                                      : _rascunhosPendentes.isEmpty
                                      ? Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.check_circle_outline,
                                                size: 48,
                                                color: Colors.grey.shade300,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Nenhum rascunho pendente',
                                                style: TextStyle(
                                                  color: Colors.grey.shade500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: _rascunhosPendentes.length,
                                          itemBuilder: (context, index) {
                                            final d =
                                                _rascunhosPendentes[index];
                                            final isSelected =
                                                _rascunhoSelecionado?.id ==
                                                d.id;
                                            return ListTile(
                                              selected: isSelected,
                                              selectedTileColor: corLaranja
                                                  .withOpacity(0.08),
                                              leading: Icon(
                                                Icons.description,
                                                color: isSelected
                                                    ? corLaranja
                                                    : Colors.grey,
                                              ),
                                              title: Text(
                                                d.masterListName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              subtitle: Text(
                                                'ID: ${d.id.substring(0, 8)}...',
                                              ),
                                              trailing: const Icon(
                                                Icons.arrow_forward_ios,
                                                size: 14,
                                              ),
                                              onTap: () =>
                                                  _carregarDetalhesDoRascunho(
                                                    d,
                                                  ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 16),

                        // PAINEL DIREITO: Detalhes
                        Expanded(
                          flex: 3,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: _rascunhoSelecionado == null
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.touch_app_outlined,
                                          size: 48,
                                          color: Colors.grey.shade300,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Selecione um rascunho para analisar',
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : _loadingDetalhes
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Header do detalhe
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _rascunhoSelecionado!
                                                        .masterListName,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const Text(
                                                    'Status: PENDENTE',
                                                    style: TextStyle(
                                                      color: corLaranja,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.red.shade600,
                                                foregroundColor: Colors.white,
                                              ),
                                              icon: const Icon(Icons.close),
                                              label: const Text('Rejeitar'),
                                              onPressed: () =>
                                                  _atualizarStatusRascunho(
                                                    'rejected',
                                                  ),
                                            ),
                                            const SizedBox(width: 8),
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.green.shade600,
                                                foregroundColor: Colors.white,
                                              ),
                                              icon: const Icon(Icons.check),
                                              label: const Text('Aprovar'),
                                              onPressed: () =>
                                                  _atualizarStatusRascunho(
                                                    'approved',
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Divider(height: 1),

                                      Expanded(
                                        child: SingleChildScrollView(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                '📦 Itens com Preço Alterado',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              _itensAlterados.isEmpty
                                                  ? const Text(
                                                      'Nenhum item individual alterado neste rascunho.',
                                                      style: TextStyle(
                                                        color: Colors.grey,
                                                        fontSize: 13,
                                                      ),
                                                    )
                                                  : Card(
                                                      elevation: 0,
                                                      shape: RoundedRectangleBorder(
                                                        side: BorderSide(
                                                          color: Colors
                                                              .grey
                                                              .shade200,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                      child: ListView.separated(
                                                        shrinkWrap: true,
                                                        physics:
                                                            const NeverScrollableScrollPhysics(),
                                                        itemCount:
                                                            _itensAlterados
                                                                .length,
                                                        separatorBuilder:
                                                            (_, __) =>
                                                                const Divider(
                                                                  height: 1,
                                                                ),
                                                        itemBuilder: (context, i) {
                                                          final item =
                                                              _itensAlterados[i];
                                                          double margem =
                                                              (item['margin_pct']
                                                                      as num?)
                                                                  ?.toDouble() ??
                                                              0.0;
                                                          return ListTile(
                                                            dense: true,
                                                            title: Text(
                                                              'Produto: ${item['product_id']}',
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                            subtitle: Text(
                                                              'De: R\$ ${item['old_price']} ➔ Para: R\$ ${item['new_price']}',
                                                            ),
                                                            trailing: Text(
                                                              '${margem >= 0 ? "+" : ""}${margem.toStringAsFixed(2)}%',
                                                              style: TextStyle(
                                                                color:
                                                                    margem >= 0
                                                                    ? Colors
                                                                          .green
                                                                    : Colors
                                                                          .red,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                              const SizedBox(height: 24),
                                              const Text(
                                                '⚡ Regras de Replicação / Exceções',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              _regrasExcecao.isEmpty
                                                  ? const Text(
                                                      'Nenhuma regra ou exceção vinculada a este rascunho.',
                                                      style: TextStyle(
                                                        color: Colors.grey,
                                                        fontSize: 13,
                                                      ),
                                                    )
                                                  : ListView.builder(
                                                      shrinkWrap: true,
                                                      physics:
                                                          const NeverScrollableScrollPhysics(),
                                                      itemCount:
                                                          _regrasExcecao.length,
                                                      itemBuilder: (context, i) {
                                                        final regra =
                                                            _regrasExcecao[i];
                                                        final targetList =
                                                            regra['price_lists']
                                                                as Map<
                                                                  String,
                                                                  dynamic
                                                                >?;
                                                        final nomeFilha =
                                                            targetList?['description'] ??
                                                            'Lista Destino';
                                                        String nivelHumano;
                                                        String detalhe = '';

                                                        switch (regra['level']) {
                                                          case 'full_table':
                                                            nivelHumano =
                                                                'Tabela inteira';
                                                            break;
                                                          case 'material_group':
                                                            nivelHumano =
                                                                'Grupo';
                                                            detalhe =
                                                                regra['reference_desc'] ??
                                                                regra['cluster_id'] ??
                                                                '';
                                                            break;
                                                          case 'specific_material':
                                                            nivelHumano =
                                                                'Material';
                                                            detalhe =
                                                                regra['reference_desc'] ??
                                                                regra['material_id'] ??
                                                                '';
                                                            break;
                                                          default:
                                                            nivelHumano =
                                                                regra['level'];
                                                        }
                                                        String sufixoAjuste =
                                                            regra['adjust_type'] ==
                                                                'percentual'
                                                            ? '%'
                                                            : ' Fixo';
                                                        return Card(
                                                          color: Colors
                                                              .orange
                                                              .shade50,
                                                          elevation: 0,
                                                          margin:
                                                              const EdgeInsets.only(
                                                                bottom: 6,
                                                              ),
                                                          child: ListTile(
                                                            dense: true,
                                                            leading: const Icon(
                                                              Icons.rule,
                                                              color:
                                                                  Colors.orange,
                                                            ),
                                                            title: Text(
                                                              'Aplicar em: $nomeFilha',
                                                            ),
                                                            subtitle: Text(
                                                              'Nível: $nivelHumano${detalhe.isNotEmpty ? " ($detalhe)" : ""} ➔ Ajuste: ${regra['value']}$sufixoAjuste',
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
