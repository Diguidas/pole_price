import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pole_price/models/material_preco.dart';
import 'package:pole_price/models/pricelist_model.dart';
import 'package:pole_price/models/pricing_cluster_item.dart';
import 'package:pole_price/models/pricing_policy_model.dart';
import 'package:pole_price/models/regra_ajuste.dart';
import 'package:pole_price/service/preco_service.dart';
import 'package:pole_price/service/pricing_policy_service.dart';
import 'package:pole_price/service/sap_sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SapModo { lista, grupo }

class PrecoController extends ChangeNotifier {
  String? draftIdAtivo; // id do rascunho em edição
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

  PrecoController._internal(this.service)
    : pricingPolicyService = PricingPolicyService(service.supabase);

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  final PriceService service;
  final PricingPolicyService pricingPolicyService;

  // ── Estado principal ─────────────────────────────────────────────────
  List<PriceList> listas = [];
  List<MaterialPreco> materiais = [];
  List<MaterialPreco> filtrados = [];

  List<String> targets = [];
  List<RegraAjuste> regras = [];

  // ── Política da lista mãe (mãe/filha) ─────────────────────────────────
  PricingPolicy? politicaAtual;

  // ── Vínculo de preço pai/filho dentro do agrupamento ──────────────────
  // Registry para forçar uma linha específica da tabela a resincronizar seus
  // TextEditingControllers quando outro material do mesmo agrupamento muda
  // o PPC Novo dela por tabela (cada _ItemMaterial mantém estado próprio por
  // ValueKey(codigo), então mutar o MaterialPreco de fora não atualiza o
  // texto do campo sozinho).
  final Map<String, VoidCallback> _refreshCallbacks = {};
  void registerRefresh(String codigo, VoidCallback cb) =>
      _refreshCallbacks[codigo] = cb;
  void unregisterRefresh(String codigo) => _refreshCallbacks.remove(codigo);
  void refreshMaterial(String codigo) => _refreshCallbacks[codigo]?.call();

  /// Aplica o vínculo de preço (pai/filho) do agrupamento de [editado] após
  /// o PPC Novo dele ter sido alterado: se [editado] é pai, recalcula os
  /// filhos diretos; se é filho, recalcula o pai e propaga aos irmãos
  /// (outros filhos do mesmo pai).
  void aplicarVinculoAgrupamento(MaterialPreco editado) {
    if (editado.agrupamentoPreco == null) return;
    final irmaos = materiais
        .where(
          (m) =>
              m.codigo != editado.codigo &&
              m.agrupamentoPreco == editado.agrupamentoPreco,
        )
        .toList();

    if (editado.materialPaiCode == null) {
      // editado é pai — atualiza filhos diretos
      for (final filho in irmaos) {
        if (filho.materialPaiCode == editado.codigo &&
            filho.excecaoPrecoPct != null) {
          filho.ppcNovoOverride =
              (editado.ppcNovoEfetivo ?? 0) * (1 + filho.excecaoPrecoPct!);
          _sincronizarNovoPreco(filho);
          refreshMaterial(filho.codigo);
        }
      }
      return;
    }

    // editado é filho — recalcula o pai e propaga aos outros filhos dele
    final pctEditado = editado.excecaoPrecoPct;
    if (pctEditado == null || pctEditado == -1) return;
    MaterialPreco? pai;
    for (final m in irmaos) {
      if (m.codigo == editado.materialPaiCode) {
        pai = m;
        break;
      }
    }
    if (pai == null) return;

    final novoPaiPpc = (editado.ppcNovoEfetivo ?? 0) / (1 + pctEditado);
    pai.ppcNovoOverride = novoPaiPpc;
    _sincronizarNovoPreco(pai);
    refreshMaterial(pai.codigo);

    for (final outro in irmaos) {
      if (outro.codigo != editado.codigo &&
          outro.materialPaiCode == pai.codigo &&
          outro.excecaoPrecoPct != null) {
        outro.ppcNovoOverride = novoPaiPpc * (1 + outro.excecaoPrecoPct!);
        _sincronizarNovoPreco(outro);
        refreshMaterial(outro.codigo);
      }
    }
  }

  /// Propaga o PPC Novo recalculado para `novoPreco` — é esse campo (não o
  /// override) que o fluxo de "Salvar para aprovação" usa para decidir o que
  /// entra no rascunho. Sem isso, o material vinculado recalcula na tela mas
  /// some do rascunho salvo (aparece como "Sem alteração" no Histórico).
  void _sincronizarNovoPreco(MaterialPreco m) {
    final ppvCx = m.ppvCxNovo;
    if (ppvCx != null) m.novoPreco = ppvCx;
  }

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

      if (materiais.isNotEmpty) {
        // Enriquece com clusterId da tabela products
        try {
          final codigos = materiais.map((m) => m.codigo).toList();
          final prodRes =
              await service.supabase
                      .from('products')
                      .select('code, pricing_cluster_id')
                      .inFilter('code', codigos)
                  as List;

          final Map<String, String> clusterMap = {};
          for (final p in prodRes) {
            final code = p['code']?.toString();
            final cid = p['pricing_cluster_id']?.toString();
            if (code != null && cid != null) clusterMap[code] = cid;
          }

          materiais = materiais
              .map(
                (m) => MaterialPreco(
                  codigo: m.codigo,
                  description: m.description,
                  precoAtual: m.precoAtual,
                  novoPreco: m.novoPreco,
                  cpv: m.cpv,
                  dedPct: m.dedPct,
                  dvPct: m.dvPct,
                  margemFlat: m.margemFlat,
                  margemOferta: m.margemOferta,
                  ppcHistorico: m.ppcHistorico,
                  clusterId: clusterMap[m.codigo],
                  agrupamentoPreco: m.agrupamentoPreco,
                  materialPaiCode: m.materialPaiCode,
                  excecaoPrecoPct: m.excecaoPrecoPct,
                  datab: m.datab,
                  datbi: m.datbi,
                  kgSug: m.kgSug,
                  pesoUnidade: m.pesoUnidade,
                  pesoCaixa: m.pesoCaixa,
                  unidadeVenda: m.unidadeVenda,
                  konwa: m.konwa,
                  kmein: m.kmein,
                  krech: m.krech,
                  mxwrt: m.mxwrt,
                  sapStatus: m.sapStatus,
                  origemMaterial: m.origemMaterial,
                  bloqueado: m.bloqueado,
                  inativo: m.inativo,
                ),
              )
              .toList();
        } catch (_) {
          // Falha no enriquecimento não bloqueia a tela
        }

        filtrados = _aplicarFiltrosLocais(materiais);
      }
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
    // Adia o rebuild para o próximo microtask — o botão de delete responde
    // imediatamente ao toque, sem travar enquanto a lista é reconstruída.
    Future.microtask(() {
      filtrados = materiais.where((mat) => !mat.removido).toList();
      notifyListeners();
    });
  }

  /// Remove vários materiais da sessão de edição de uma vez (seleção múltipla).
  void removerMateriais(Iterable<MaterialPreco> lista) {
    for (final m in lista) {
      m.removido = true;
    }
    Future.microtask(() {
      filtrados = materiais.where((mat) => !mat.removido).toList();
      notifyListeners();
    });
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
      notifyListeners(); // só notifica quando há reordenação real
    }
    // Sem promover: o _ItemMaterial já gerencia sua própria UI via setState —
    // não precisa reconstruir a tela inteira a cada blur/onChange.
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
  /*   void iniciarNovaSessao({PriceList? listaMae}) {
    draftIdAtivo = null;
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
  } */

  void iniciarNovaSessao({PriceList? listaMae}) {
    materiais = [];
    filtrados = [];
    targets = [];
    regras = [];
    selecionada = listaMae ?? selecionada;
    vigenciaGlobalDatab = null;
    vigenciaGlobalDatbi = null;
    erro = null;
    draftIdAtivo = null;
    // ← REMOVIDO: pltyp, kdgrp, datab, datbi, databOp, datbiOp, modo
    // Esses são setados pelo goToPrecos/goToPrecosComRascunho antes da tela montar
    notifyListeners();
  }

  /// Busca a Política vinculada à lista mãe atual (`pltyp`) e, quando
  /// [preencherTargets] é true, popula `targets` automaticamente com as
  /// demais listas da mesma política (regra mãe/filha). Se a lista mãe não
  /// pertence a nenhuma política, `politicaAtual` fica null e `targets`
  /// permanece inalterado (seleção manual, comportamento de hoje).
  Future<void> sincronizarPoliticaDaListaMae({bool preencherTargets = true}) async {
    politicaAtual = null;
    if (pltyp == null) {
      notifyListeners();
      return;
    }
    politicaAtual = await pricingPolicyService.getPolicyForLista(pltyp!);
    if (politicaAtual != null && preencherTargets) {
      targets = politicaAtual!.listas
          .map((l) => l.pltyp)
          .where((id) => id != pltyp)
          .toList();
    }
    notifyListeners();
  }

  /// Gera as regras efetivas para salvar/exibir: as manuais (`regras`) mais
  /// uma regra automática de exceção de margem por lista filha da política
  /// atual (nível Tabela, percentual) — reproduz o efeito da exceção de
  /// margem da Política sem duplicar o mecanismo de RegraAjuste.
  List<RegraAjuste> get regrasEfetivas {
    final efetivas = List<RegraAjuste>.from(regras);
    final politica = politicaAtual;
    if (politica == null || politica.margemFlat == null) return efetivas;

    PolicyPriceList? maeInfo;
    for (final l in politica.listas) {
      if (l.pltyp == pltyp) {
        maeInfo = l;
        break;
      }
    }
    final margemMae = politica.margemFlat! + (maeInfo?.excecaoFlatPct ?? 0);
    if (margemMae >= 1) return efetivas;

    for (final lista in politica.listas) {
      if (lista.pltyp == pltyp) continue;
      if (!targets.contains(lista.pltyp)) continue;
      final jaTemRegraManual = efetivas.any(
        (r) => r.targetListId == lista.pltyp && r.nivel == 'Tabela',
      );
      if (jaTemRegraManual) continue;
      if (lista.excecaoFlatPct == null || lista.excecaoFlatPct == 0) continue;

      final margemFilha = politica.margemFlat! + lista.excecaoFlatPct!;
      if (margemFilha >= 1) continue;
      final deltaPct = ((1 - margemFilha) / (1 - margemMae) - 1) * 100;

      efetivas.add(
        RegraAjuste(
          targetListId: lista.pltyp,
          nivel: 'Tabela',
          tipo: 'Percentual',
          valor: deltaPct,
          clusterNome: '[Política] ${politica.name}',
        ),
      );
    }
    return efetivas;
  }

  /// [sapStatus]: status SAP a ser gravado em todos os itens do draft.
  ///   '' = ativo/normal, 'L' = bloqueado p/ liberação, 'X' = deletado
  Future<String> salvar({String? justificativa, String sapStatus = ''}) async {
    return service.saveDraft(
      masterListId: selecionada?.id,
      materiais: materiais.where((m) => !m.removido).toList(),
      targets: targets,
      regras: regrasEfetivas,
      modo: modo == SapModo.grupo ? 'grupo' : 'lista',
      kdgrp: kdgrp,
      vigenciaDatab: _toSapDate(vigenciaGlobalDatab),
      vigenciaDatbi: _toSapDate(vigenciaGlobalDatbi),
      justificativa: justificativa,
      sapStatus: sapStatus,
      draftStatus: 'pending',
    );
  }

  /// Salva como rascunho (status = 'draft'), sem enviar para aprovação.
  /// Retorna o id do draft criado.
  Future<String> salvarRascunho() async {
    final id = await service.saveDraft(
      draftId: draftIdAtivo,
      masterListId: selecionada?.id,
      materiais: materiais.where((m) => !m.removido).toList(),
      targets: targets,
      regras: regrasEfetivas,
      modo: modo == SapModo.grupo ? 'grupo' : 'lista',
      kdgrp: kdgrp,
      vigenciaDatab: _toSapDate(vigenciaGlobalDatab),
      vigenciaDatbi: _toSapDate(vigenciaGlobalDatbi),
      justificativa: null,
      sapStatus: '',
      draftStatus: 'draft',
    );
    draftIdAtivo = id; // ← agora executa antes do return
    return id;
  }

  Future<void> carregarRascunho(String draftId) async {
    draftIdAtivo = draftId;
    loading = true;
    erro = null;
    notifyListeners();

    try {
      // 1. Cabeçalho do draft (apenas colunas que existem)
      final draft = await service.supabase
          .from('price_drafts')
          .select(
            'master_list_id, vigencia_datab, vigencia_datbi, justificativa',
          )
          .eq('id', draftId)
          .single();

      pltyp = draft['master_list_id']?.toString();

      // Restaura vigência global (formato SAP YYYYMMDD → DD/MM/AAAA para o controller)
      vigenciaGlobalDatab = _fromSapDate(draft['vigencia_datab']?.toString());
      vigenciaGlobalDatbi = _fromSapDate(draft['vigencia_datbi']?.toString());

      // 2. Busca as 3 tabelas filhas + metadados do primeiro item em paralelo
      final results = await Future.wait([
        service.supabase
            .from('price_draft_items')
            .select()
            .eq('draft_id', draftId),
        service.supabase
            .from('price_draft_targets')
            .select('target_list_id')
            .eq('draft_id', draftId),
        service.supabase
            .from('price_draft_exceptions')
            .select()
            .eq('draft_id', draftId),
      ]);

      final itens = results[0] as List;
      final targetRes = results[1] as List;
      final excRes = results[2] as List;

      // 3. Modo e kdgrp vêm dos itens
      final primeiroItem = itens.isNotEmpty ? itens.first : null;
      modo = primeiroItem?['modo'] == 'grupo' ? SapModo.grupo : SapModo.lista;
      kdgrp = primeiroItem?['kdgrp']?.toString();

      // 4. Targets (restaurados do rascunho salvo — não sobrescrever pela política)
      targets = targetRes
          .map((r) => r['target_list_id']?.toString())
          .whereType<String>()
          .toList();
      await sincronizarPoliticaDaListaMae(preencherTargets: false);

      // 5. Descriptions dos materiais via materials (tem description direto)
      final codigos = itens
          .map((r) => r['product_id']?.toString())
          .whereType<String>()
          .toList();

      final Map<String, String> descMap = {};
      if (codigos.isNotEmpty && pltyp != null) {
        final matsRes = await service.supabase
            .from('materials')
            .select('product_id, description')
            .eq('price_list_id', pltyp!)
            .inFilter('product_id', codigos);
        for (final m in matsRes as List) {
          descMap[m['product_id'].toString()] =
              m['description']?.toString() ?? '';
        }
        // Fallback para products.name se não encontrou em materials
        final semDesc = codigos.where((c) => !descMap.containsKey(c)).toList();
        if (semDesc.isNotEmpty) {
          final prodRes = await service.supabase
              .from('products')
              .select('code, name')
              .inFilter('code', semDesc);
          for (final p in prodRes as List) {
            descMap[p['code'].toString()] = p['name']?.toString() ?? '';
          }
        }
      }

      // Vínculo de preço pai/filho + agrupamento — atributo do material
      // (tabela materials, coluna material_code), não da lista.
      final Map<String, Map<String, dynamic>> vinculoMap = {};
      if (codigos.isNotEmpty) {
        final vinculoRes = await service.supabase
            .from('materials')
            .select(
              'material_code, agrupamento_preco, material_pai_code, excecao_preco_pct',
            )
            .inFilter('material_code', codigos);
        for (final r in vinculoRes as List) {
          final code = r['material_code']?.toString();
          if (code != null) vinculoMap[code] = r;
        }
      }

      // 6. Monta materiais
      materiais = itens.map((row) {
        final codigo = row['product_id']?.toString() ?? '';
        final vinculo = vinculoMap[codigo];
        return MaterialPreco(
          codigo: codigo,
          description: descMap[codigo] ?? codigo,
          precoAtual: double.tryParse(row['old_price'].toString()) ?? 0,
          agrupamentoPreco: vinculo?['agrupamento_preco']?.toString(),
          materialPaiCode: vinculo?['material_pai_code']?.toString(),
          excecaoPrecoPct: vinculo?['excecao_preco_pct'] != null
              ? double.tryParse(vinculo!['excecao_preco_pct'].toString())
              : null,
          novoPreco: (row['price_edited'] == true)
              ? double.tryParse(row['new_price'].toString()) ?? 0
              : 0,
          datab: row['datab']?.toString(),
          datbi: row['datbi']?.toString(),
          konwa: row['konwa']?.toString(),
          kmein: row['kmein']?.toString(),
          krech: row['krech']?.toString(),
          mxwrt: row['mxwrt'] != null
              ? double.tryParse(row['mxwrt'].toString())
              : null,
          sapStatus: row['sap_status']?.toString() ?? '',
          origemMaterial: row['origem_material'] == 'manual'
              ? OrigemMaterial.manual
              : OrigemMaterial.sap,
          bloqueado: false,
          inativo: false,
          cpv: row['cpv'] != null
              ? double.tryParse(row['cpv'].toString())
              : null,
          kgSug: row['kg_sug'] != null
              ? double.tryParse(row['kg_sug'].toString())
              : null,
          // ← NOVOS: restaura overrides de sessão persistidos no draft
          ppcNovoOverride: row['ppc_novo'] != null
              ? double.tryParse(row['ppc_novo'].toString())
              : null,
          ppcOfertaOverride: row['ppc_oferta'] != null
              ? double.tryParse(row['ppc_oferta'].toString())
              : null,
          margemFlatOverride: row['margem_flat_override'] != null
              ? double.tryParse(row['margem_flat_override'].toString())
              : null,
          margemOfertaOverride: row['margem_oferta_override'] != null
              ? double.tryParse(row['margem_oferta_override'].toString())
              : null,
        );
      }).toList();

      // Após: materiais = itens.map(...).toList();

      try {
        final codigos = materiais.map((m) => m.codigo).toList();
        final prodRes =
            await service.supabase
                    .from('products')
                    .select('code, pricing_cluster_id')
                    .inFilter('code', codigos)
                as List;

        final Map<String, String> clusterMap = {};
        for (final p in prodRes) {
          final code = p['code']?.toString();
          final cid = p['pricing_cluster_id']?.toString();
          if (code != null && cid != null) clusterMap[code] = cid;
        }

        materiais = materiais
            .map(
              (m) => MaterialPreco(
                codigo: m.codigo,
                description: m.description,
                precoAtual: m.precoAtual,
                novoPreco: m.novoPreco,
                cpv: m.cpv,
                dedPct: m.dedPct,
                dvPct: m.dvPct,
                margemFlat: m.margemFlat,
                margemOferta: m.margemOferta,
                ppcHistorico: m.ppcHistorico,
                clusterId: clusterMap[m.codigo],
                agrupamentoPreco: m.agrupamentoPreco,
                materialPaiCode: m.materialPaiCode,
                excecaoPrecoPct: m.excecaoPrecoPct,
                datab: m.datab,
                datbi: m.datbi,
                kgSug: m.kgSug,
                pesoUnidade: m.pesoUnidade,
                pesoCaixa: m.pesoCaixa,
                unidadeVenda: m.unidadeVenda,
                konwa: m.konwa,
                kmein: m.kmein,
                krech: m.krech,
                mxwrt: m.mxwrt,
                sapStatus: m.sapStatus,
                origemMaterial: m.origemMaterial,
                bloqueado: m.bloqueado,
                inativo: m.inativo,
                ppcNovoOverride: m.ppcNovoOverride,
                ppcOfertaOverride: m.ppcOfertaOverride,
                margemFlatOverride: m.margemFlatOverride,
                margemOfertaOverride: m.margemOfertaOverride,
              ),
            )
            .toList();
      } catch (_) {}

      filtrados = List.from(materiais);

      // 7. Regras de ajuste
      regras = excRes.map((row) {
        return RegraAjuste(
          targetListId: row['target_list_id']?.toString() ?? '',
          nivel: _mapNivelDe(row['level']?.toString()),
          tipo: row['adjust_type'] == 'fixed' ? 'Fixo' : 'Percentual',
          valor: double.tryParse(row['value'].toString()) ?? 0,
          clusterId: row['cluster_id']?.toString(),
          clusterNome: row['reference_desc']?.toString(),
          materialId: row['material_id']?.toString(),
          materialNome: row['reference_desc']?.toString(),
        );
      }).toList();
    } catch (e) {
      erro = 'Erro ao carregar rascunho: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// YYYYMMDD → DD/MM/AAAA
  String? _fromSapDate(String? sap) {
    if (sap == null || sap.length < 8) return null;
    return '${sap.substring(6, 8)}/${sap.substring(4, 6)}/${sap.substring(0, 4)}';
  }

  String _mapNivelDe(String? level) => switch (level) {
    'material_group' => 'Grupo',
    'specific_material' => 'Material',
    _ => 'Geral',
  };

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
