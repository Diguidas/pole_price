import 'package:flutter/material.dart';
import 'package:pole_price/models/material_preco.dart';
import 'package:pole_price/models/pricelist_model.dart';
import 'package:pole_price/models/pricing_cluster_item.dart';
import 'package:pole_price/models/regra_ajuste.dart';
import 'package:pole_price/service/preco_service.dart';

class PrecoController extends ChangeNotifier {
  final PriceService service;

  PrecoController(this.service);

  List<PriceList> listas = [];
  List<MaterialPreco> materiais = [];
  List<MaterialPreco> filtrados = [];

  List<String> targets = [];
  List<RegraAjuste> regras = [];

  PriceList? selecionada;

  bool loading = false;

  // ── Filtro por cluster (vindo de GruposScreen) ──────────────────────
  String? filtroClusterId;

  void filtrarPorCluster(String clusterId) {
    filtroClusterId = clusterId;
    filtrados = materiais.where((m) => m.clusterId == clusterId).toList();
    notifyListeners();
  }

  // ── Clusters e materiais para o painel de Exceções ──────────────────
  List<PricingClusterItem> clusters = [];
  List<MaterialPreco> materiaisDoCluster = [];
  bool loadingClusters = false;
  bool loadingMateriaisCluster = false;

  Future<void> carregarClusters() async {
    if (clusters.isNotEmpty) return; // já carregado
    loadingClusters = true;
    notifyListeners();

    clusters = await service.getClusters();

    loadingClusters = false;
    notifyListeners();
  }

  Future<void> carregarMateriaisDoCluster(String clusterId) async {
    materiaisDoCluster = [];
    loadingMateriaisCluster = true;
    notifyListeners();

    materiaisDoCluster = await service.getMaterialsByCluster(clusterId);

    loadingMateriaisCluster = false;
    notifyListeners();
  }

  // ── Init / seleção de lista ──────────────────────────────────────────
  Future<void> init() async {
    loading = true;
    notifyListeners();

    listas = await service.getLists();

    // Só re-sincroniza se já havia uma lista selecionada
    if (selecionada != null) {
      final id = selecionada!.id;
      selecionada = listas.cast<PriceList?>().firstWhere(
        (l) => l?.id == id,
        orElse: () => null,
      );
    }

    loading = false;
    notifyListeners();
  }

  Future<void> selecionarLista(PriceList l) async {
    selecionada = l;
    loading = true;
    notifyListeners();

    materiais = await service.getMaterials(l.id);
    filtrados = List.from(materiais);

    loading = false;
    notifyListeners();
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

  Future<void> salvar() async {
    await service.saveDraft(
      masterListId: selecionada?.id,
      materiais: materiais,
      targets: targets,
      regras: regras,
    );
  }

  void toggleTarget(String id) {
    if (targets.contains(id)) {
      targets.remove(id);
    } else {
      if (!targets.contains(id)) targets.add(id); // garante sem duplicata
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
}
