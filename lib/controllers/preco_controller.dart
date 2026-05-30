import 'package:flutter/material.dart';
import 'package:pole_price/models/material_preco.dart';
import 'package:pole_price/models/pricelist_model.dart';
import 'package:pole_price/models/pricing_cluster_item.dart';
import 'package:pole_price/models/regra_ajuste.dart';
import 'package:pole_price/service/preco_service.dart';
import 'package:pole_price/service/sap_sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PrecoController extends ChangeNotifier {
  // ── Singleton por sessão ─────────────────────────────────────────────
  // Evita que targets e regras sejam perdidos ao navegar entre telas.
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

  final PriceService service;

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

  void filtrarPorCluster(String clusterId) {
    filtroClusterId = clusterId;
    filtrados = materiais.where((m) => m.clusterId == clusterId).toList();
    notifyListeners();
  }

  List<PricingClusterItem> clusters = [];
  List<MaterialPreco> materiaisDoCluster = [];
  bool loadingClusters = false;
  bool loadingMateriaisCluster = false;

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
    // Se já tiver listas carregadas, não recarrega — preserva o estado.
    if (listas.isNotEmpty) return;

    loading = true;
    erro = null;
    notifyListeners();

    try {
      listas = await service.getLists();
    } catch (e) {
      erro = 'Erro ao carregar listas de preço: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Força recarregamento das listas (ex: após sync SAP).
  Future<void> recarregarListas() async {
    loading = true;
    erro = null;
    notifyListeners();

    try {
      listas = await service.getLists();

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

  void atualizarPreco(MaterialPreco m, double novo) {
    m.novoPreco = novo;
    notifyListeners();
  }

  void buscar(String q) {
    filtrados = materiais.where((m) {
      return m.codigo.contains(q) ||
          m.description.toLowerCase().contains(q.toLowerCase());
    }).toList();
    notifyListeners();
  }

  Future<String> salvar() async {
    return service.saveDraft(
      masterListId: selecionada?.id,
      materiais: materiais,
      targets: targets,
      regras: regras,
    );
  }

  Future<SapSyncResult> atualizarDoSap() async {
    syncingSap = true;
    erro = null;
    notifyListeners();
    try {
      final result = await service.syncFromSap(listId: selecionada?.id);
      if (selecionada != null) {
        await selecionarLista(selecionada!);
      }
      return result;
    } catch (e) {
      erro = 'Erro ao sincronizar do SAP: $e';
      rethrow;
    } finally {
      syncingSap = false;
      notifyListeners();
    }
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
}