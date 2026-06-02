import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pole_price/models/material_preco.dart';
import 'package:pole_price/models/pricelist_model.dart';
import 'package:pole_price/models/pricing_cluster_item.dart';
import 'package:pole_price/models/regra_ajuste.dart';
import 'package:pole_price/service/preco_service.dart';
import 'package:pole_price/service/sap_sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SapModo { lista, grupo }

class PrecoController extends ChangeNotifier {
  // ── Singleton por sessão ─────────────────────────────────────────────
  static PrecoController? _instance;

  static PrecoController get instance {
    _instance ??= PrecoController._internal(
      PriceService(Supabase.instance.client),
    );
    return _instance!;
  }

  /// Chame apenas em logout ou quando quiser resetar o estado completamente.
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }

  PrecoController._internal(this.service);

  @override
  void dispose() {
    tableScrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  final PriceService service;

  // ── Scroll ────────────────────────────────────────────────────────────
  /// ScrollController compartilhado com o ListView de TabelaPrecos.
  /// Criado aqui (lazy) para sobreviver rebuilds do widget.
  final ScrollController tableScrollController = ScrollController();

  void scrollToTop() {
    if (tableScrollController.hasClients) {
      tableScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Estado principal ─────────────────────────────────────────────────
  List<PriceList> listas = [];
  List<MaterialPreco> materiais = [];
  List<MaterialPreco> filtrados = [];

  List<String> targets = [];
  List<RegraAjuste> regras = [];

  PriceList? selecionada;

  bool loading = false;
  bool syncingSap = false;
  String? erro;

  String? filtroClusterId;

  // ── Vigência global da nova lista ────────────────────────────────────
  String? vigenciaGlobalDatab; // formato DD/MM/AAAA (vindo do picker)
  String? vigenciaGlobalDatbi;

  // ── Estado SAP (novo) ────────────────────────────────────────────────
  SapModo modo = SapModo.lista;
  String? pltyp; // código da lista SAP selecionada
  String? kdgrp; // código do grupo (só em modo grupo)
  DateTime? datab; // início da vigência
  DateTime? datbi; // fim da vigência
  // Em PrecoController (junto com datab/datbi):
  String? databOp; // ex: 'GE', 'EQ', 'LE', 'NE'
  String? datbiOp;

  // ── Filtros de status do material ────────────────────────────────────
  // null = não filtra, 'X' = incluir apenas marcados, '' = excluir marcados
  String? kznepFilter; // inativo (KZNEP)
  String? loevmFilter; // bloqueado (LOEVM_KO)

  // ── Clusters ─────────────────────────────────────────────────────────
  List<PricingClusterItem> clusters = [];
  List<MaterialPreco> materiaisDoCluster = [];
  bool loadingClusters = false;
  bool loadingMateriaisCluster = false;

  void filtrarPorCluster(String clusterId) {
    filtroClusterId = clusterId;
    filtrados = materiais
        .where((m) => m.clusterId == clusterId && !m.removido)
        .toList();
    notifyListeners();
  }

  Future<void> carregarClusters() async {
    if (clusters.isNotEmpty) return;
    loadingClusters = true;
    erro = null;
    notifyListeners();

    try {
      clusters = await service.getClusters();
    } catch (e) {
      erro = 'Erro ao carregar clusters: $e';
    } finally {
      loadingClusters = false;
      notifyListeners();
    }
  }

  Future<void> carregarMateriaisDoCluster(String clusterId) async {
    materiaisDoCluster = [];
    loadingMateriaisCluster = true;
    erro = null;
    notifyListeners();

    try {
      materiaisDoCluster = await service.getMaterialsByCluster(clusterId);
    } catch (e) {
      erro = 'Erro ao carregar materiais do cluster: $e';
    } finally {
      loadingMateriaisCluster = false;
      notifyListeners();
    }
  }

  Future<void> init() async {
    if (listas.isNotEmpty) return;

    loading = true;
    erro = null;
    notifyListeners();

    try {
      listas = await service.getLists();

      // Tabela vazia → busca catálogo do SAP e recarrega
      if (listas.isEmpty) {
        await service.sincronizarCatalogo();
        listas = await service.getLists();
      }
    } catch (e) {
      erro = 'Erro ao carregar listas de preço: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Chama a edge function sync-price-catalog para popular price_lists e price_groups.
  Future<void> _sincronizarCatalogo() async {
    final res = await service.supabase.functions.invoke('sync-price-catalog');
    if (res.status != 200) {
      throw Exception('Falha ao sincronizar catálogo SAP (${res.status})');
    }
    // Recarrega após sincronizar
    listas = await service.getLists();
  }

  Future<void> recarregarListas() async {
    loading = true;
    erro = null;
    notifyListeners();

    try {
      listas = await service.getLists();

      // Mesma lógica: catálogo vazio → sincroniza
      if (listas.isEmpty) {
        await service.sincronizarCatalogo();
        listas = await service.getLists();
      }

      if (selecionada != null) {
        final id = selecionada!.id;
        selecionada = listas.cast<PriceList?>().firstWhere(
          (l) => l?.id == id,
          orElse: () => null,
        );
      }
    } catch (e) {
      erro = 'Erro ao carregar listas de preço: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selecionarLista(PriceList l) async {
    selecionada = l;
    await recarregarMateriais();
  }

  /// @deprecated — use buscarDoSap(). Mantido para compatibilidade.
  Future<void> recarregarMateriais() async {
    if (selecionada == null) return;
    loading = true;
    erro = null;
    notifyListeners();

    try {
      materiais = await service.getMaterials(selecionada!.id);
      filtrados = List.from(materiais);
    } catch (e) {
      erro = 'Erro ao carregar materiais: $e';
      materiais = [];
      filtrados = [];
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Busca os preços ao vivo do SAP conforme o modo configurado.
  ///
  /// Deve ser chamado no initState de PrecoScreen após receber os parâmetros
  /// de navegação (modo, pltyp, kdgrp, datab, datbi).
  Future<void> buscarDoSap() async {
    if (pltyp == null || pltyp!.isEmpty) {
      erro = 'Selecione uma lista SAP antes de buscar.';
      notifyListeners();
      return;
    }
    if (modo == SapModo.grupo && (kdgrp == null || kdgrp!.isEmpty)) {
      erro = 'Selecione um grupo SAP para o modo Lista+Grupo.';
      notifyListeners();
      return;
    }

    loading = true;
    erro = null;
    notifyListeners();

    try {
      final databStr = _formatDate(datab);
      final datbiStr = _formatDate(datbi);

      final kznepP = _kznepSapParams();
      final loevmP = _loevmSapParams();

      if (modo == SapModo.lista) {
        materiais = await service.sapSync.fetchFromSapLista(
          pltyp: pltyp!,
          datab: databStr,
          datbi: datbiStr,
          databOp: databOp,
          datbiOp: datbiOp,
          kznep: kznepP.value,
          kznepOp: kznepP.op,
          loevm: loevmP.value,
          loevmOp: loevmP.op,
        );
      } else {
        materiais = await service.sapSync.fetchFromSapGrupo(
          pltyp: pltyp!,
          kdgrp: kdgrp!,
          datab: databStr,
          datbi: datbiStr,
          databOp: databOp,
          datbiOp: datbiOp,
          kznep: kznepP.value,
          kznepOp: kznepP.op,
          loevm: loevmP.value,
          loevmOp: loevmP.op,
        );
      }

      if (materiais.isNotEmpty) filtrados = _aplicarFiltrosLocais(materiais);
    } catch (e) {
      erro = 'Erro ao buscar do SAP: $e';
      materiais = [];
      filtrados = [];
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Remove um material da sessão de edição (apenas local, não afeta o SAP).
  void removerMaterial(MaterialPreco m) {
    m.removido = true;
    filtrados = materiais.where((m) => !m.removido).toList();
    notifyListeners();
  }

  /// Adiciona um material buscado manualmente (origem = manual).
  void adicionarMaterial(MaterialPreco m) {
    materiais.add(m);
    filtrados = materiais.where((m) => !m.removido).toList();
    notifyListeners();
  }

  void atualizarPreco(MaterialPreco m, double novo, {bool promover = false}) {
    m.novoPreco = novo;
    if (promover) {
      // Move o item para o topo de materiais e filtrados
      materiais.remove(m);
      materiais.insert(0, m);
      filtrados = _aplicarFiltrosLocais(materiais);
    }
    notifyListeners();
  }

  void atualizarVigencia(MaterialPreco m, String? datab, String? datbi) {
    m.datab = datab;
    m.datbi = datbi;
    notifyListeners();
  }

  Timer? _debounceTimer;

  void buscar(String q) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      final base = _aplicarFiltrosLocais(materiais);
      if (q.isEmpty) {
        filtrados = base;
      } else {
        filtrados = base.where((m) {
          return m.codigo.contains(q) ||
              m.description.toLowerCase().contains(q.toLowerCase());
        }).toList();
      }
      notifyListeners();
    });
  }

  /// Limpa os dados de edição da sessão anterior sem destruir o singleton.
  void iniciarNovaSessao({PriceList? listaMae}) {
    materiais = [];
    filtrados = [];
    targets = [];
    regras = [];
    // selecionada NÃO é zerada aqui — vem do parâmetro
    selecionada =
        listaMae ?? selecionada; // mantém a que já estava se não passar nada
    vigenciaGlobalDatab = null;
    vigenciaGlobalDatbi = null;
    erro = null;
    notifyListeners();
  }

  /// [sapStatus]: status SAP a ser gravado em todos os itens do draft.
  ///   '' = ativo/normal, 'L' = bloqueado p/ liberação, 'X' = deletado
  Future<String> salvar({String? justificativa, String sapStatus = ''}) async {
    return service.saveDraft(
      masterListId: selecionada?.id,
      materiais: materiais.where((m) => !m.removido).toList(),
      targets: targets,
      regras: regras,
      modo: modo == SapModo.grupo ? 'grupo' : 'lista',
      kdgrp: kdgrp,
      vigenciaDatab: _toSapDate(vigenciaGlobalDatab),
      vigenciaDatbi: _toSapDate(vigenciaGlobalDatbi),
      justificativa: justificativa,
      sapStatus: sapStatus,
    );
  }

  /// Converte DD/MM/AAAA → YYYYMMDD (formato SAP).
  String? _toSapDate(String? ddmmaaaa) {
    if (ddmmaaaa == null || ddmmaaaa.length < 10) return null;
    final parts = ddmmaaaa.split('/');
    if (parts.length != 3) return null;
    return '${parts[2]}${parts[1]}${parts[0]}';
  }

  void toggleTarget(String id) {
    if (targets.contains(id)) {
      targets.remove(id);
    } else {
      targets.add(id);
    }
    notifyListeners();
  }

  void addRegra(RegraAjuste regra) {
    regras.add(regra);
    notifyListeners();
  }

  void removeRegra(RegraAjuste regra) {
    regras.remove(regra);
    notifyListeners();
  }

  void limparErro() {
    erro = null;
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Aplica filtros locais (apenas remoção de itens marcados como removido).
  /// Filtros de inativo/bloqueado são agora enviados diretamente ao SAP.
  List<MaterialPreco> _aplicarFiltrosLocais(List<MaterialPreco> lista) {
    return lista.where((m) => !m.removido).toList();
  }

  /// Reaaplica os filtros locais sem nova busca no SAP.
  void aplicarFiltrosLocais() {
    filtrados = _aplicarFiltrosLocais(materiais);
    notifyListeners();
  }

  /// Converte o filtro de status (null/'X'/'E') em valor e operador SAP.
  ({String? value, String? op}) _kznepSapParams() {
    return switch (kznepFilter) {
      'X' => (value: 'I', op: 'EQ'),
      'E' => (value: 'I', op: 'NE'),
      _ => (value: null, op: null),
    };
  }

  ({String? value, String? op}) _loevmSapParams() {
    return switch (loevmFilter) {
      'X' => (value: 'X', op: 'EQ'),
      'E' => (value: 'X', op: 'NE'),
      _ => (value: null, op: null),
    };
  }

  /// Converte DateTime para o formato SAP (YYYYMMDD).
  String? _formatDate(DateTime? dt) {
    if (dt == null) return null;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }
}