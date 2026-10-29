// definir_aprovacoes_screen.dart
// Fatorado em widgets privados para manter o arquivo legível.
import 'package:flutter/material.dart';
import 'package:pole_price/controllers/background_task_controller.dart';
import 'package:pole_price/controllers/permissao_controller.dart';
import 'package:pole_price/models/draft_aprova_model.dart';
import 'package:pole_price/models/draft_lista.dart';
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
  static const _laranja = Color(0xFFE8793A);

  late final DraftPricingService _draftService;

  bool _loadingDrafts = true;
  bool _loadingDetalhes = false;
  bool _aprovando = false;

  List<DraftAprovacao> _rascunhosPendentes = [];
  DraftAprovacao? _rascunhoSelecionado;

  List<Map<String, dynamic>> _materiais = [];
  String _detalheCabecalho = '';
  String _datab = '';
  String _datbi = '';
  String _filtroTab = 'todos';
  String _busca = '';
  final Set<String> _listasExpandidas = {};

  // Listas do rascunho (vigência + status de envio por lista)
  List<DraftLista> _listas = [];
  bool _listasPersistidas = true;
  final Set<String> _listasSel = {};
  // Rascunhos com um envio ao SAP em andamento (evita envio em duplicidade)
  final Set<String> _enviando = {};

  @override
  void initState() {
    super.initState();
    _draftService = DraftPricingService(Supabase.instance.client);
    _buscarRascunhosPendentes();
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  Future<void> _buscarRascunhosPendentes({bool carregarInicial = true}) async {
    setState(() => _loadingDrafts = true);
    try {
      // Materiais que o SAP não confirmou numa aprovação anterior — o draft
      // já está 'approved', mas continua aparecendo aqui com uma tag de
      // "Reprocessar" até esses itens específicos serem reenviados.
      final falhaRows = await Supabase.instance.client
          .from('price_draft_items')
          .select('draft_id, product_id, sap_erro')
          .not('sap_erro', 'is', null);

      final falhasPorDraft = <String, List<Map<String, dynamic>>>{};
      for (final r in falhaRows as List) {
        final id = r['draft_id']?.toString();
        if (id == null) continue;
        falhasPorDraft.putIfAbsent(id, () => []).add({
          'matnr': r['product_id']?.toString() ?? '',
          'erro': r['sap_erro']?.toString() ?? 'motivo desconhecido',
        });
      }
      final idsComFalha = falhasPorDraft.keys.toList();

      final pendentesRes = await Supabase.instance.client
          .from('price_drafts')
          .select('id, status, created_at, master_list_id, created_by_email, justificativa')
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final comFalhaRes = idsComFalha.isEmpty
          ? <dynamic>[]
          : await Supabase.instance.client
                .from('price_drafts')
                .select('id, status, created_at, master_list_id, created_by_email, justificativa')
                .inFilter('id', idsComFalha)
                .neq('status', 'pending') // evita duplicar quem já veio acima
                .order('created_at', ascending: false);

      final drafts = [...pendentesRes as List, ...comFalhaRes];

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
        final id = j['id']?.toString() ?? '';
        return DraftAprovacao.fromJson(
          {...j, 'lista_nome': nomePorPltyp[pltyp] ?? pltyp ?? ''},
          falhas: falhasPorDraft[id] ?? const [],
        );
      }).toList();

      setState(() => _rascunhosPendentes = lista);

      final idInicial = widget.draftIdInicial;
      if (carregarInicial && idInicial != null && mounted) {
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
      _datab = '';
      _datbi = '';
      _listasExpandidas.clear();
      _listas = [];
      _listasSel.clear();
      _filtroTab = 'todos';
      _busca = '';
    });
    try {
      final preview = await _draftService.buildPreview(draft.id);
      final listasRes = await _draftService.carregarListasDoDraft(draft.id);

      // Vigência do cabeçalho: só a global do rascunho (rascunhos antigos).
      // A de cada lista aparece no painel "Listas e vigência".
      final vigRow = await Supabase.instance.client
          .from('price_drafts')
          .select('vigencia_datab, vigencia_datbi')
          .eq('id', draft.id)
          .maybeSingle();

      var linhas = preview.materiais.map((m) => m.toRowMap()).toList();

      // Draft em modo "Reprocessar": mostra só os materiais que o SAP não
      // confirmou (mãe e/ou filhas) — os que já deram certo não precisam
      // aparecer de novo aqui.
      if (draft.temFalhas) {
        final matnrsComFalha = draft.falhas
            .map((f) => f['matnr']?.toString())
            .whereType<String>()
            .toSet();
        linhas = linhas
            .where((m) => matnrsComFalha.contains(m['product_id']?.toString()))
            .toList();
      }

      setState(() {
        _materiais = linhas;
        _detalheCabecalho = preview.resumo;
        _datab = vigRow?['vigencia_datab']?.toString() ?? '';
        _datbi = vigRow?['vigencia_datbi']?.toString() ?? '';
        _listas = listasRes.listas;
        _listasPersistidas = listasRes.persistido;
        // Já vêm marcadas as listas pendentes que têm vigência definida; as
        // sem vigência só entram na seleção depois de receberem uma.
        _listasSel
          ..clear()
          ..addAll(
            listasRes.listas
                .where((l) => l.pendente && l.temVigencia)
                .map((l) => l.pltyp),
          );
      });
    } catch (e) {
      _snack('Erro ao carregar detalhes: $e', Colors.red);
    } finally {
      setState(() => _loadingDetalhes = false);
    }
  }

  /// Publica um draft no SAP e grava quem aprovou. [pltyps] = só essas listas
  /// (as demais continuam pendentes); null = todas as pendentes. Se algum
  /// material não for confirmado, lança SapPushFalhasException (ver
  /// DraftPricingService.applyDraft).
  Future<int> _executarAprovacao(
    String draftId,
    String reviewerEmail, {
    List<String>? pltyps,
  }) async {
    final priceService = PriceService(Supabase.instance.client);
    final total = await priceService.approveDraft(draftId, pltyps: pltyps);

    await Supabase.instance.client
        .from('price_drafts')
        .update({
          'reviewed_by_email': reviewerEmail,
          'reviewed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', draftId);

    return total;
  }

  /// Confirma, com a vigência de cada lista, o envio ao SAP.
  Future<bool> _confirmarEnvio(List<DraftLista> alvo, int restantes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Enviar ${alvo.length} lista(s) ao SAP?',
          style: const TextStyle(fontSize: 16),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final l in alvo)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '• ${l.nome}  —  '
                    '${DraftLista.formatar(l.datab)} → ${DraftLista.formatar(l.datbi)}'
                    '${l.totalMateriais > 0 ? '  (${l.qtdEnviados} materiais)' : ''}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              if (restantes > 0) ...[
                const SizedBox(height: 10),
                Text(
                  '$restantes lista(s) continuam pendentes de aprovação.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _laranja),
            child: const Text('Enviar ao SAP'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Dispara a publicação em segundo plano (BackgroundTaskController) e
  /// libera a tela na hora — o usuário pode navegar livremente enquanto o
  /// SAP processa. [pltyps] = só essas listas; null = todas as pendentes.
  /// O resultado (sucesso ou lista de materiais com falha) fica disponível
  /// no card flutuante no canto inferior da tela.
  Future<void> _publicarListas({List<String>? pltyps}) async {
    if (_rascunhoSelecionado == null) return;
    final draft = _rascunhoSelecionado!;
    final draftId = draft.id;

    // Com a tabela por lista disponível, valida e confirma o que vai ao SAP.
    List<String>? alvoPltyps = pltyps;
    var restantes = 0;
    if (_listasPersistidas) {
      final alvo = _listas
          .where((l) => l.pendente && (pltyps == null || pltyps.contains(l.pltyp)))
          .toList();
      if (alvo.isEmpty) {
        _snack('Selecione ao menos uma lista pendente.', Colors.orange);
        return;
      }
      final semVigencia = alvo.where((l) => !l.temVigencia).toList();
      if (semVigencia.isNotEmpty) {
        // Desmarca as sem vigência para o usuário poder reenviar só as demais.
        setState(() {
          for (final l in semVigencia) {
            _listasSel.remove(l.pltyp);
          }
        });
        _snack(
          'Sem vigência (desmarcadas): ${semVigencia.map((l) => l.nome).join(', ')}. '
          'Defina a vigência delas ou envie só as demais.',
          Colors.orange,
        );
        return;
      }
      restantes = _listas.where((l) => l.pendente).length - alvo.length;
      if (!await _confirmarEnvio(alvo, restantes)) return;
      alvoPltyps = alvo.map((l) => l.pltyp).toList();
    }

    final reviewerEmail =
        Supabase.instance.client.auth.currentUser?.email ?? 'desconhecido';
    final sufixo = alvoPltyps == null ? 'todas' : alvoPltyps.join('-');
    final taskId = 'aprovar_draft_${draftId}_$sufixo';

    _enviando.add(draftId);
    BackgroundTaskController.instance.run(
      id: taskId,
      title: alvoPltyps == null
          ? 'Publicar preços — ${draft.masterListName}'
          : 'Publicar preços — ${draft.masterListName} (${alvoPltyps.length} lista(s))',
      action: () =>
          _executarAprovacao(draftId, reviewerEmail, pltyps: alvoPltyps),
    );

    // Ao concluir (sucesso ou falha), atualiza a lista de pendentes; se ainda
    // restarem listas pendentes, recarrega este rascunho para mostrar o status.
    _aguardarConclusaoEAtualizar(taskId, draftId: draftId);

    _snack(
      'Publicação enviada para o SAP em segundo plano. '
      'Acompanhe pelo card no canto inferior da tela.',
      Colors.blueGrey,
    );
    if (restantes == 0) {
      _limparSelecao();
    } else {
      setState(() {}); // trava os botões enquanto o envio roda
    }
  }

  /// Listas pendentes com vigência definida — é o que o botão do topo envia.
  List<DraftLista> get _listasProntas =>
      _listas.where((l) => l.pendente && l.temVigencia).toList();

  void _aprovarRascunho() => _publicarListas(
    pltyps: _listasPersistidas
        ? _listasProntas.map((l) => l.pltyp).toList()
        : null,
  );

  // ── Vigência por lista ────────────────────────────────────────────────────

  void _toggleListaSel(String pltyp) => setState(() {
    if (!_listasSel.remove(pltyp)) _listasSel.add(pltyp);
  });

  void _toggleTodasListas() => setState(() {
    final pendentes = _listas.where((l) => l.pendente).map((l) => l.pltyp);
    final todas = pendentes.every(_listasSel.contains);
    _listasSel.clear();
    if (!todas) _listasSel.addAll(pendentes);
  });

  Future<void> _definirVigencia(List<DraftLista> alvo, String titulo) async {
    if (_rascunhoSelecionado == null || alvo.isEmpty) return;
    final r = await showDialog<({String datab, String datbi})>(
      context: context,
      builder: (_) => _VigenciaDialog(
        titulo: titulo,
        databInicial: alvo.first.datab,
        datbiInicial: alvo.first.datbi,
      ),
    );
    if (r == null || !mounted) return;
    try {
      await _draftService.salvarVigenciaListas(
        _rascunhoSelecionado!.id,
        alvo.map((l) => l.pltyp).toList(),
        datab: r.datab,
        datbi: r.datbi,
      );
      setState(() {
        for (final l in alvo) {
          l.datab = r.datab;
          l.datbi = r.datbi;
          _listasSel.add(l.pltyp); // lista com vigência nova já fica marcada
        }
      });
      _snack(
        'Vigência ${DraftLista.formatar(r.datab)} → ${DraftLista.formatar(r.datbi)} '
        'aplicada a ${alvo.length} lista(s).',
        Colors.green,
      );
    } catch (e) {
      _snack('Erro ao salvar vigência: $e', Colors.red);
    }
  }

  void _vigenciaSelecionadas() => _definirVigencia(
    _listas.where((l) => l.pendente && _listasSel.contains(l.pltyp)).toList(),
    'Vigência das listas selecionadas',
  );

  void _vigenciaTodas() => _definirVigencia(
    _listas.where((l) => l.pendente).toList(),
    'Vigência de todas as listas pendentes',
  );

  /// Mostra quais materiais NÃO vão para a lista [l] (escolhidos na criação).
  void _verExcluidos(DraftLista l) {
    final nomes = <String, String>{
      for (final m in _materiais)
        m['product_id'].toString(): m['description']?.toString() ?? '',
    };
    final codigos = l.excluidos.toList()..sort();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${codigos.length} material(is) fora de ${l.nome}',
          style: const TextStyle(fontSize: 16),
        ),
        content: SizedBox(
          width: 420,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final c in codigos)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '$c  —  ${(nomes[c] ?? '').isEmpty ? '(sem descrição)' : nomes[c]}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _vigenciaLista(DraftLista l) =>
      _definirVigencia([l], 'Vigência — ${l.nome}');

  /// Reenvia só os materiais marcados com falha deste draft (sap_erro),
  /// também em segundo plano — não precisa reabrir/recriar a lista.
  void _reprocessarRascunho() {
    if (_rascunhoSelecionado == null) return;
    final draft = _rascunhoSelecionado!;
    final draftId = draft.id;
    final taskId = 'reprocessar_draft_$draftId';

    BackgroundTaskController.instance.run(
      id: taskId,
      title: 'Reprocessar falhas — ${draft.masterListName}',
      action: () =>
          PriceService(Supabase.instance.client).reprocessarFalhas(draftId),
    );

    _aguardarConclusaoEAtualizar(taskId);

    _snack(
      'Reprocessamento enviado para o SAP em segundo plano. '
      'Acompanhe pelo card no canto inferior da tela.',
      Colors.blueGrey,
    );
    _limparSelecao();
  }

  void _aguardarConclusaoEAtualizar(String taskId, {String? draftId}) {
    late final VoidCallback listener;
    listener = () {
      final task = BackgroundTaskController.instance.tasks
          .where((t) => t.id == taskId)
          .firstOrNull;
      if (task == null || task.status == BgTaskStatus.running) return;
      BackgroundTaskController.instance.removeListener(listener);
      if (draftId != null) _enviando.remove(draftId);
      if (!mounted) return;
      () async {
        // Sem recarregar o rascunho inicial da URL: só atualiza a lista e, se
        // o rascunho enviado continua selecionado e pendente, o recarrega.
        await _buscarRascunhosPendentes(carregarInicial: draftId == null);
        if (!mounted || draftId == null) return;
        if (_rascunhoSelecionado?.id != draftId) {
          setState(() {}); // destrava os botões
          return;
        }
        final d = _rascunhosPendentes
            .where((x) => x.id == draftId)
            .firstOrNull;
        if (d != null) await _carregarDetalhesRascunho(d);
      }();
    };
    BackgroundTaskController.instance.addListener(listener);
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
    _datab = '';
    _datbi = '';
    _listasExpandidas.clear();
    _listas = [];
    _listasSel.clear();
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
      backgroundColor: const Color(0xFFF7F5F2),
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
                    datab: _datab,
                    datbi: _datbi,
                    filtroTab: _filtroTab,
                    busca: _busca,
                    listasExpandidas: _listasExpandidas,
                    kpis: kpis,
                    aprovando:
                        _aprovando || _enviando.contains(_rascunhoSelecionado!.id),
                    listas: _listas,
                    listasSel: _listasSel,
                    listasPersistidas: _listasPersistidas,
                    onToggleListaSel: _toggleListaSel,
                    onToggleTodasListas: _toggleTodasListas,
                    onVigenciaSelecionadas: _vigenciaSelecionadas,
                    onVigenciaTodas: _vigenciaTodas,
                    onVigenciaLista: _vigenciaLista,
                    onVerExcluidos: _verExcluidos,
                    qtdProntas: _listasProntas.length,
                    podeAprovar: PermissaoController.instance.podeAprovar,
                    countListasFilhas: _countListasFilhas(),
                    gruposOrdenados: _gruposOrdenados(),
                    materiaisFiltrados: _materiaisFiltrados,
                    onAprovar: _aprovarRascunho,
                    onRejeitar: _rejeitarRascunho,
                    onReprocessar: _reprocessarRascunho,
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
    if (origem.startsWith('Ajuste manual')) return 'Exceção manual';
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
  static const _laranja = Color(0xFFE8793A);
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
    // Extrai só o nome da parte local do email (antes do @)
    final nomeExibicao = draft.createdByEmail != null && draft.createdByEmail!.isNotEmpty
        ? draft.createdByEmail!.split('@').first
        : 'Desconhecido';

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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nomeExibicao,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: selected
                                  ? _laranja
                                  : Colors.grey.shade900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (draft.temFalhas)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              'Reprocessar',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (draft.justificativa != null &&
                        draft.justificativa!.isNotEmpty)
                      Text(
                        draft.justificativa!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
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
  static const _laranja = Color(0xFFE8793A);

  final DraftAprovacao draft;
  final List<Map<String, dynamic>> materiais;
  final String detalheCabecalho;
  final String datab;
  final String datbi;
  final String filtroTab;
  final String busca;
  final Set<String> listasExpandidas;
  final _KpiData? kpis;
  final bool aprovando;
  final List<DraftLista> listas;
  final Set<String> listasSel;
  final bool listasPersistidas;
  final void Function(String) onToggleListaSel;
  final VoidCallback onToggleTodasListas;
  final VoidCallback onVigenciaSelecionadas;
  final VoidCallback onVigenciaTodas;
  final void Function(DraftLista) onVigenciaLista;
  final void Function(DraftLista) onVerExcluidos;
  final int qtdProntas; // listas pendentes com vigência = o que o botão envia
  final bool podeAprovar;
  final int countListasFilhas;
  final List<MapEntry<String, List<Map<String, dynamic>>>> gruposOrdenados;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)
  materiaisFiltrados;
  final VoidCallback onAprovar;
  final VoidCallback onRejeitar;
  final VoidCallback onReprocessar;
  final void Function(String) onToggleLista;
  final void Function(String) onFiltroTab;
  final void Function(String) onBusca;

  const _PainelDetalhes({
    required this.draft,
    required this.materiais,
    required this.detalheCabecalho,
    required this.datab,
    required this.datbi,
    required this.filtroTab,
    required this.busca,
    required this.listasExpandidas,
    required this.kpis,
    required this.aprovando,
    required this.listas,
    required this.listasSel,
    required this.listasPersistidas,
    required this.onToggleListaSel,
    required this.onToggleTodasListas,
    required this.onVigenciaSelecionadas,
    required this.onVigenciaTodas,
    required this.onVigenciaLista,
    required this.onVerExcluidos,
    required this.qtdProntas,
    required this.podeAprovar,
    required this.countListasFilhas,
    required this.gruposOrdenados,
    required this.materiaisFiltrados,
    required this.onAprovar,
    required this.onRejeitar,
    required this.onReprocessar,
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
          datab: datab,
          datbi: datbi,
          aprovando: aprovando,
          podeAprovar: podeAprovar,
          rotuloAprovar: !listasPersistidas
              ? 'Aprovar e publicar'
              : 'Enviar ao SAP ($qtdProntas)',
          // Com envio por lista, só habilita quando há lista pronta (com vigência).
          podeEnviar: !listasPersistidas || qtdProntas > 0,
          // Depois de publicar alguma lista não dá mais para rejeitar tudo.
          podeRejeitar: !listas.any((l) => l.foiPublicada),
          onAprovar: onAprovar,
          onRejeitar: onRejeitar,
          onReprocessar: onReprocessar,
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!draft.temFalhas && listas.isNotEmpty) ...[
                        _PainelListas(
                          listas: listas,
                          selecionadas: listasSel,
                          persistido: listasPersistidas,
                          podeAprovar: podeAprovar,
                          ocupado: aprovando,
                          onToggle: onToggleListaSel,
                          onToggleTodas: onToggleTodasListas,
                          onVigenciaSelecionadas: onVigenciaSelecionadas,
                          onVigenciaTodas: onVigenciaTodas,
                          onVigenciaLista: onVigenciaLista,
                          onVerExcluidos: onVerExcluidos,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (kpis != null)
                        _KpiCards(
                          kpis: kpis!,
                          countListasFilhas: countListasFilhas,
                        ),
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
                Padding(
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Listas do rascunho: vigência por lista + envio parcial ao SAP
// ─────────────────────────────────────────────────────────────────────────────
class _PainelListas extends StatelessWidget {
  static const _laranja = Color(0xFFE8793A);

  final List<DraftLista> listas;
  final Set<String> selecionadas;
  final bool persistido;
  final bool podeAprovar;
  final bool ocupado;
  final void Function(String pltyp) onToggle;
  final VoidCallback onToggleTodas;
  final VoidCallback onVigenciaSelecionadas;
  final VoidCallback onVigenciaTodas;
  final void Function(DraftLista) onVigenciaLista;
  final void Function(DraftLista) onVerExcluidos;

  const _PainelListas({
    required this.listas,
    required this.selecionadas,
    required this.persistido,
    required this.podeAprovar,
    required this.ocupado,
    required this.onToggle,
    required this.onToggleTodas,
    required this.onVigenciaSelecionadas,
    required this.onVigenciaTodas,
    required this.onVigenciaLista,
    required this.onVerExcluidos,
  });

  @override
  Widget build(BuildContext context) {
    if (listas.isEmpty) return const SizedBox.shrink();

    if (!persistido) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Text(
          'Para definir a vigência e enviar por lista, aplique a migração '
          'supabase_migration_price_draft_lists.sql no Supabase. Enquanto '
          'isso, todas as listas são enviadas juntas, com a vigência do rascunho.',
          style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
        ),
      );
    }

    final pendentes = listas.where((l) => l.pendente).toList();
    final selecionadasPendentes =
        pendentes.where((l) => selecionadas.contains(l.pltyp)).toList();
    final todasMarcadas =
        pendentes.isNotEmpty && selecionadasPendentes.length == pendentes.length;
    final podeAgir = podeAprovar && !ocupado;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.account_tree_outlined,
                    size: 17, color: _laranja),
                const Text(
                  'Listas e vigência',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${listas.where((l) => l.enviada).length} de ${listas.length} enviadas',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(width: 8),
                if (podeAgir && pendentes.isNotEmpty) ...[
                  OutlinedButton.icon(
                    onPressed: onToggleTodas,
                    icon: Icon(
                      todasMarcadas
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 16,
                    ),
                    label: Text(
                        todasMarcadas ? 'Desmarcar todas' : 'Selecionar todas'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selecionadasPendentes.isEmpty
                        ? null
                        : onVigenciaSelecionadas,
                    icon: const Icon(Icons.date_range, size: 16),
                    label: Text(
                        'Vigência p/ selecionadas (${selecionadasPendentes.length})'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onVigenciaTodas,
                    icon: const Icon(Icons.date_range, size: 16),
                    label: const Text('Vigência p/ todas'),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          for (final l in listas)
            _linha(context, l, podeAgir),
          if (podeAgir && pendentes.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Text(
                'O envio ao SAP é feito pelo botão no topo da página e leva as '
                'listas pendentes que já têm vigência. As marcações servem só '
                'para aplicar a mesma vigência a várias listas de uma vez.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _linha(BuildContext context, DraftLista l, bool podeAgir) {
    final marcada = selecionadas.contains(l.pltyp);
    final (rotulo, bg, fg) = switch (l.status) {
      'sent' => ('Enviada', Colors.green.shade50, Colors.green.shade700),
      'error' => ('Enviada com erro', Colors.red.shade50, Colors.red.shade700),
      _ => ('Pendente', _laranja.withOpacity(0.1), _laranja),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: l.pendente && podeAgir
                ? Checkbox(
                    value: marcada,
                    activeColor: _laranja,
                    onChanged: (_) => onToggle(l.pltyp),
                  )
                : Icon(
                    l.enviada
                        ? Icons.check_circle_outline
                        : l.comErro
                            ? Icons.error_outline
                            : Icons.lock_outline,
                    size: 18,
                    color: l.enviada
                        ? Colors.green.shade600
                        : l.comErro
                            ? Colors.red.shade400
                            : Colors.grey.shade400,
                  ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        l.nome,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l.isMaster ? 'Mãe' : 'Filha',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      l.pltyp,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                    if (l.totalMateriais > 0) ...[
                      Text('  ·  ',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade400)),
                      InkWell(
                        onTap: l.excluidos.isEmpty
                            ? null
                            : () => onVerExcluidos(l),
                        child: Text(
                          l.excluidos.isEmpty
                              ? '${l.totalMateriais} materiais'
                              : '${l.qtdEnviados} de ${l.totalMateriais} materiais',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: l.excluidos.isEmpty
                                ? FontWeight.w400
                                : FontWeight.w700,
                            color: l.excluidos.isEmpty
                                ? Colors.grey.shade500
                                : _laranja,
                            decoration: l.excluidos.isEmpty
                                ? null
                                : TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(Icons.date_range,
                    size: 14,
                    color: l.temVigencia ? _laranja : Colors.red.shade400),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    l.temVigencia
                        ? '${DraftLista.formatar(l.datab)} → ${DraftLista.formatar(l.datbi)}'
                        : 'Sem vigência',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: l.temVigencia
                          ? Colors.grey.shade800
                          : Colors.red.shade500,
                    ),
                  ),
                ),
                if (l.pendente && podeAgir)
                  IconButton(
                    tooltip: 'Editar vigência desta lista',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 17),
                    onPressed: () => onVigenciaLista(l),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              rotulo,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Diálogo para escolher a vigência (início e fim, ou sem fim = 31/12/9999).
class _VigenciaDialog extends StatefulWidget {
  final String titulo;
  final String? databInicial; // AAAAMMDD
  final String? datbiInicial;
  const _VigenciaDialog({
    required this.titulo,
    this.databInicial,
    this.datbiInicial,
  });

  @override
  State<_VigenciaDialog> createState() => _VigenciaDialogState();
}

class _VigenciaDialogState extends State<_VigenciaDialog> {
  static const _laranja = Color(0xFFE8793A);
  static const _semFim = '99991231';

  late DateTime? _inicio = DraftLista.deSap(widget.databInicial);
  late DateTime? _fim = (widget.datbiInicial == null ||
          widget.datbiInicial == _semFim)
      ? null
      : DraftLista.deSap(widget.datbiInicial);
  late bool _semDataFinal =
      widget.datbiInicial == null || widget.datbiInicial == _semFim;
  String? _erro;

  Future<DateTime?> _escolher(DateTime? atual) => showDatePicker(
        context: context,
        initialDate: atual ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );

  String _fmt(DateTime? d) => d == null
      ? 'Escolher data'
      : DraftLista.formatar(DraftLista.paraSap(d));

  void _confirmar() {
    if (_inicio == null) {
      setState(() => _erro = 'Informe a data de início.');
      return;
    }
    if (!_semDataFinal) {
      if (_fim == null) {
        setState(() => _erro = 'Informe a data final ou marque "Sem data final".');
        return;
      }
      if (_fim!.isBefore(_inicio!)) {
        setState(() => _erro = 'A data final não pode ser anterior ao início.');
        return;
      }
    }
    Navigator.of(context).pop((
      datab: DraftLista.paraSap(_inicio!),
      datbi: _semDataFinal ? _semFim : DraftLista.paraSap(_fim!),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Válido a partir de',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.event, size: 16),
              label: Text(_fmt(_inicio)),
              onPressed: () async {
                final d = await _escolher(_inicio);
                if (d != null) setState(() => _inicio = d);
              },
            ),
            const SizedBox(height: 14),
            const Text('Válido até',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_available, size: 16),
              label: Text(_semDataFinal ? '31/12/9999' : _fmt(_fim)),
              onPressed: _semDataFinal
                  ? null
                  : () async {
                      final d = await _escolher(_fim ?? _inicio);
                      if (d != null) setState(() => _fim = d);
                    },
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: _laranja,
              value: _semDataFinal,
              onChanged: (v) => setState(() => _semDataFinal = v ?? false),
              title: const Text('Sem data final (31/12/9999)',
                  style: TextStyle(fontSize: 12.5)),
            ),
            if (_erro != null) ...[
              const SizedBox(height: 4),
              Text(_erro!,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          style: FilledButton.styleFrom(backgroundColor: _laranja),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cabeçalho do painel de detalhes
// ─────────────────────────────────────────────────────────────────────────────
class _Cabecalho extends StatelessWidget {
  static const _laranja = Color(0xFFE8793A);
  final DraftAprovacao draft;
  final String datab;
  final String datbi;
  final bool aprovando;
  final bool podeAprovar;
  final String rotuloAprovar;
  final bool podeEnviar;
  final bool podeRejeitar;
  final VoidCallback onAprovar;
  final VoidCallback onRejeitar;
  final VoidCallback onReprocessar;

  const _Cabecalho({
    required this.draft,
    required this.datab,
    required this.datbi,
    required this.aprovando,
    required this.podeAprovar,
    required this.rotuloAprovar,
    required this.podeEnviar,
    required this.podeRejeitar,
    required this.onAprovar,
    required this.onRejeitar,
    required this.onReprocessar,
  });

  @override
  Widget build(BuildContext context) {
    // Formata datas de vigência
    String _fmtData(String? raw) {
      if (raw == null || raw.isEmpty) return '—';
      // Suporta formato ISO (yyyy-mm-dd) e SAP (yyyymmdd)
      String s = raw.replaceAll('-', '');
      if (s.length == 8) {
        return '${s.substring(6, 8)}/${s.substring(4, 6)}/${s.substring(0, 4)}';
      }
      if (raw.length >= 10) {
        final parts = raw.substring(0, 10).split('-');
        if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
      return raw;
    }

    final temVigencia = datab.isNotEmpty || datbi.isNotEmpty;

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
                'Revisão de rascunho',
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
                    const Text(
                      'Aprovação de preços',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Criado por + data
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
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
                        Text(
                          'Criado em ${draft.createdAtFormatado}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    // Vigência em destaque
                    if (temVigencia) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _laranja.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _laranja.withOpacity(0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.date_range,
                                size: 15, color: _laranja),
                            const SizedBox(width: 6),
                            Text(
                              'Vigência: ${_fmtData(datab)} → ${_fmtData(datbi)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _laranja,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Materiais que o SAP não confirmou numa aprovação anterior
                    if (draft.temFalhas) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 15,
                                  color: Colors.red.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${draft.falhas.length} material(is) não confirmado(s) no SAP',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 160),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: draft.falhas
                                      .map(
                                        (f) => Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            '${f['matnr']}  —  ${f['erro']}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red.shade600,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              draft.temFalhas
                  ? _badge('Com pendências', Colors.red.shade50, Colors.red.shade700)
                  : _badge('Pendente', _laranja.withOpacity(0.1), _laranja),
              const SizedBox(width: 12),
              if (podeAprovar && draft.temFalhas) ...[
                ElevatedButton.icon(
                  onPressed: aprovando ? null : onReprocessar,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    'Reprocessar (${draft.falhas.length})',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                ),
              ] else if (podeAprovar) ...[
                if (podeRejeitar) ...[
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
                ],
                ElevatedButton.icon(
                  onPressed: (aprovando || !podeEnviar) ? null : onAprovar,
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
                  label: Text(aprovando ? 'Aprovando...' : rotuloAprovar),
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
  static const _laranja = Color(0xFFE8793A);
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
  static const _laranja = Color(0xFFE8793A);
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
    if (origem.startsWith('Ajuste manual')) return 'Exceção manual';
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
  static const _laranja = Color(0xFFE8793A);
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
    if (origem.startsWith('Ajuste manual')) return 'Exceção manual';
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
  static const _laranja = Color(0xFFE8793A);
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
  static const _laranja = Color(0xFFE8793A);
  final Map<String, dynamic> item;
  const _MaterialRow({required this.item});

  static String _statusLabel(Map<String, dynamic> item) {
    if (item['foi_editado'] != true) return 'Sem alteração';
    final origem = item['origem']?.toString() ?? '';
    if (origem.startsWith('Ajuste manual')) return 'Exceção manual';
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
  static const _laranja = Color(0xFFE8793A);
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