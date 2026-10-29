import 'package:pole_price/models/draft_lista.dart';
import 'package:pole_price/models/material_draft_preview.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pole_price/service/supabase_paginacao.dart';

/// Lançada quando o SAP confirma o recebimento do push, mas reporta que um
/// ou mais materiais não foram efetivamente gravados (BDC do lado ABAP não
/// confirmou a criação da nova vigência). O draft já foi marcado como
/// aprovado neste ponto — isto é um aviso de inconsistência, não um erro
/// que impede a aprovação.
class SapPushFalhasException implements Exception {
  final int total;
  final List<Map<String, dynamic>> falhas;

  SapPushFalhasException({required this.total, required this.falhas});

  @override
  String toString() {
    final detalhes = falhas
        .map((f) => '${f['matnr']}: ${f['erro'] ?? 'motivo desconhecido'}')
        .join('; ');
    return 'Publicado no SAP, mas $total material(is) não foram confirmados: $detalhes';
  }
}

class _RegraMatch {
  final int prioridade;
  final String adjustType;
  final double valor;

  _RegraMatch({
    required this.prioridade,
    required this.adjustType,
    required this.valor,
  });
}

/// Centraliza cálculo de preview e aplicação de drafts.
///
/// FONTE DE DADOS: exclusivamente price_draft_items (SAP → draft → aprovação).
/// A tabela `materials` não é mais consultada.
class DraftPricingService {
  final SupabaseClient supabase;

  DraftPricingService(this.supabase);

  Future<DraftPreviewResult> buildPreview(String draftId) async {
    // ── 1. Dados do draft ────────────────────────────────────────────────
    final draftData = await supabase
        .from('price_drafts')
        .select('master_list_id')
        .eq('id', draftId)
        .single();

    final String? masterListId = draftData['master_list_id'] as String?;

    // Nome da lista mãe via pltyp
    String nomeListaMae = masterListId ?? 'Lista Mãe';
    if (masterListId != null) {
      final listaRes = await supabase
          .from('price_lists')
          .select('ptext')
          .eq('pltyp', masterListId)
          .maybeSingle();
      nomeListaMae = listaRes?['ptext']?.toString() ?? masterListId;
    }

    // ── 2. Itens editados, targets e exceções em paralelo ────────────────
    final futures = await Future.wait<dynamic>([
      supabase
          .from('price_draft_items')
          .select(
            'product_id, old_price, new_price, datab, datbi, origem_material, '
            'cpv, kg_sug, ppc_novo, ppc_oferta, margem_flat_override, margem_oferta_override',
          )
          .eq('draft_id', draftId),
      supabase
          .from('price_draft_targets')
          .select('target_list_id')
          .eq('draft_id', draftId),
      supabase
          .from('price_draft_exceptions')
          .select(
            'target_list_id, level, adjust_type, value, cluster_id, material_id',
          )
          .eq('draft_id', draftId),
    ]);

    final itensRes = futures[0] as List;
    final targetsRes = futures[1] as List;
    final excecoesRes = futures[2] as List;
    final exclusoes = await carregarExclusoes(draftId);

    // ── 3. Mapa de preços da lista mãe (só editados) ─────────────────────
    // new_price = preço que o usuário digitou no SAP
    // old_price = preço que estava no SAP antes da edição
    final Map<String, double> precoNovoPorPid = {};
    final Map<String, double> precoAntigoPorPid = {};
    final Map<String, String> descricaoPorPid =
        {}; // preenchido abaixo se disponível

    // Congelados no draft — usados para reconstruir o card completo
    // (Atual/Novo/Oferta) na tela de histórico.
    final Map<String, double> cpvPorPid = {};
    final Map<String, double> kgSugPorPid = {};
    final Map<String, double> ppcNovoPorPid = {};
    final Map<String, double> ppcOfertaPorPid = {};
    final Map<String, double> margemFlatOverridePorPid = {};
    final Map<String, double> margemOfertaOverridePorPid = {};

    for (final item in itensRes) {
      final pid = item['product_id']?.toString();
      if (pid == null) continue;
      final np = _toDouble(item['new_price']);
      final op = _toDouble(item['old_price']);
      if (np != null) precoNovoPorPid[pid] = np;
      if (op != null) precoAntigoPorPid[pid] = op;

      final cpv = _toDouble(item['cpv']);
      if (cpv != null) cpvPorPid[pid] = cpv;
      final kgSug = _toDouble(item['kg_sug']);
      if (kgSug != null) kgSugPorPid[pid] = kgSug;
      final ppcNovo = _toDouble(item['ppc_novo']);
      if (ppcNovo != null) ppcNovoPorPid[pid] = ppcNovo;
      final ppcOferta = _toDouble(item['ppc_oferta']);
      if (ppcOferta != null) ppcOfertaPorPid[pid] = ppcOferta;
      final mfOverride = _toDouble(item['margem_flat_override']);
      if (mfOverride != null) margemFlatOverridePorPid[pid] = mfOverride;
      final moOverride = _toDouble(item['margem_oferta_override']);
      if (moOverride != null) margemOfertaOverridePorPid[pid] = moOverride;
    }

    // Peso/Ded%/DV%/margens da política — não são congelados por item do
    // draft, então usamos o cadastro/custo atuais para montar o card.
    final Map<String, double> pesoUnidadePorPid = {};
    final Map<String, double> pesoCaixaPorPid = {};
    final Map<String, double> dedPctPorPid = {};
    final Map<String, double> dvPctPorPid = {};
    double? margemFlatPolitica;
    double? margemOfertaPolitica;

    // Busca descrições dos produtos editados (products table, não materials)
    if (precoNovoPorPid.isNotEmpty) {
      final pids = precoNovoPorPid.keys.toList();
      final futurasExtras = await Future.wait<dynamic>([
        emBlocos(
          pids,
          (parte) => paginar((a, b) => supabase
              .from('products')
              .select('code, name')
              .inFilter('code', parte)
              .order('code')
              .range(a, b)),
        ),
        emBlocos(
          pids,
          (parte) => paginar((a, b) => supabase
              .from('materials')
              .select('material_code, peso_unidade, peso_caixa')
              .inFilter('material_code', parte)
              .order('material_code')
              .range(a, b)),
        ),
        emBlocos(
          pids,
          (parte) => paginar((a, b) => supabase
              .from('product_costs')
              .select('product_code, ded_pct, dv_pct, period')
              .inFilter('product_code', parte)
              .order('product_code')
              .order('period')
              .range(a, b)),
        ),
        if (masterListId != null)
          supabase
              .from('price_lists')
              .select('policy_id, pricing_policies(margem_flat, margem_oferta)')
              .eq('pltyp', masterListId)
              .maybeSingle()
        else
          Future<dynamic>.value(null),
      ]);

      for (final p in futurasExtras[0] as List) {
        final code = p['code']?.toString();
        final name = p['name']?.toString();
        if (code != null && name != null) descricaoPorPid[code] = name;
      }

      for (final p in futurasExtras[1] as List) {
        final code = p['material_code']?.toString();
        if (code == null) continue;
        final pu = _toDouble(p['peso_unidade']);
        final pc = _toDouble(p['peso_caixa']);
        if (pu != null) pesoUnidadePorPid[code] = pu;
        if (pc != null) pesoCaixaPorPid[code] = pc;
      }

      // 'period' pode conter formatos legados fora do padrão AAAAMM — só
      // considera períodos de 6 dígitos ao escolher o mais recente.
      final periodoRegex = RegExp(r'^\d{6}$');
      final melhorPeriodoPorPid = <String, String>{};
      for (final c in futurasExtras[2] as List) {
        final code = c['product_code']?.toString();
        final periodo = c['period']?.toString();
        if (code == null ||
            periodo == null ||
            !periodoRegex.hasMatch(periodo)) {
          continue;
        }
        final atual = melhorPeriodoPorPid[code];
        if (atual == null || periodo.compareTo(atual) > 0) {
          melhorPeriodoPorPid[code] = periodo;
        }
      }
      for (final c in futurasExtras[2] as List) {
        final code = c['product_code']?.toString();
        final periodo = c['period']?.toString();
        if (code == null || periodo != melhorPeriodoPorPid[code]) continue;
        final ded = _toDouble(c['ded_pct']);
        final dv = _toDouble(c['dv_pct']);
        if (ded != null) dedPctPorPid[code] = ded;
        if (dv != null) dvPctPorPid[code] = dv;
      }

      final listRes = futurasExtras[3] as Map<String, dynamic>?;
      if (listRes != null) {
        final policy = listRes['pricing_policies'] as Map<String, dynamic>?;
        margemFlatPolitica = _toDouble(policy?['margem_flat']);
        margemOfertaPolitica = _toDouble(policy?['margem_oferta']);
      }
    }

    final resultado = <MaterialDraftPreview>[];
    final explicacoes = <String>[];

    // ── 4. Lista mãe — apenas materiais editados ─────────────────────────
    for (final pid in precoNovoPorPid.keys) {
      final precoNovo = precoNovoPorPid[pid]!;
      final precoAntigo = precoAntigoPorPid[pid] ?? 0.0;
      final desc = descricaoPorPid[pid] ?? pid;

      resultado.add(
        MaterialDraftPreview(
          materialRowId: '', // não tem row na materials
          productId: pid,
          description: desc,
          listaId: masterListId ?? '',
          listaNome: nomeListaMae,
          tipoLista: 'mae',
          precoAntigo: precoAntigo,
          precoNovo: precoNovo,
          origem: 'Ajuste manual',
          foiEditado: precoNovo != precoAntigo,
          cpv: cpvPorPid[pid],
          kgSug: kgSugPorPid[pid],
          ppcNovo: ppcNovoPorPid[pid],
          ppcOferta: ppcOfertaPorPid[pid],
          margemFlatOverride: margemFlatOverridePorPid[pid],
          margemOfertaOverride: margemOfertaOverridePorPid[pid],
          pesoUnidade: pesoUnidadePorPid[pid],
          pesoCaixa: pesoCaixaPorPid[pid],
          dedPct: dedPctPorPid[pid],
          dvPct: dvPctPorPid[pid],
          margemFlat: margemFlatPolitica,
          margemOferta: margemOfertaPolitica,
        ),
      );
    }

    if (precoNovoPorPid.isNotEmpty) {
      explicacoes.add(
        '• ${precoNovoPorPid.length} material(is) editado(s) na lista mãe "$nomeListaMae".',
      );
    }

    if (targetsRes.isEmpty) {
      return DraftPreviewResult(
        materiais: resultado,
        resumo: explicacoes.isEmpty
            ? 'Nenhuma modificação detectada neste rascunho.'
            : explicacoes.join('\n'),
      );
    }

    // ── 5. Nomes das listas filhas ───────────────────────────────────────
    final targetIds = targetsRes
        .map((t) => t['target_list_id']?.toString())
        .whereType<String>()
        .toList();

    final listaNamesRes = await supabase
        .from('price_lists')
        .select('pltyp, ptext')
        .inFilter('pltyp', targetIds);

    final Map<String, String> nomesPorPltyp = {
      for (final l in listaNamesRes as List)
        if (l['pltyp'] != null)
          l['pltyp'].toString(): l['ptext']?.toString() ?? 'Lista Filha',
    };

    // ── 6. Clusters dos produtos editados (para aplicar exceções) ────────
    final clusterMap = await _clusterMapForProducts(
      precoNovoPorPid.keys.toList(),
    );

    // ── 7. Processa cada lista filha ─────────────────────────────────────
    for (final targetListId in targetIds) {
      final nomeListaFilha = nomesPorPltyp[targetListId] ?? targetListId;

      final regrasFilha = excecoesRes
          .where((e) => e['target_list_id']?.toString() == targetListId)
          .toList();

      if (regrasFilha.isEmpty) {
        explicacoes.add(
          '• Lista filha "$nomeListaFilha": herda preços da lista mãe.',
        );
      } else {
        final niveisTxt = regrasFilha
            .map((r) {
              final nivel = r['level']?.toString() ?? '';
              final tipo = r['adjust_type']?.toString() ?? 'percentual';
              final valor = _toDouble(r['value']) ?? 0.0;
              final sufixo = tipo == 'percentual' ? '%' : ' R\$';
              final nivelLabel = nivel == 'full_table'
                  ? 'toda a lista'
                  : nivel == 'material_group'
                  ? 'grupo específico'
                  : 'material específico';
              return '+$valor$sufixo em $nivelLabel';
            })
            .join(', ');
        explicacoes.add('• Lista filha "$nomeListaFilha": $niveisTxt.');
      }

      // Aplica regras sobre cada produto editado na mãe
      for (final pid in precoNovoPorPid.keys) {
        // Material escolhido para NÃO ir a esta lista filha.
        if (exclusoes[targetListId]?.contains(pid) ?? false) continue;
        final precoBase = precoNovoPorPid[pid]!;
        final precoAntigoMae = precoAntigoPorPid[pid] ?? 0.0;
        final desc = descricaoPorPid[pid] ?? pid;
        final clusterId = clusterMap[pid];

        double precoNovo;
        String origemStr;

        if (regrasFilha.isEmpty) {
          precoNovo = precoBase;
          origemStr = 'Herda lista mãe';
        } else {
          final melhorRegra = _melhorRegra(
            regrasFilha,
            productId: pid,
            clusterId: clusterId,
          );
          if (melhorRegra != null) {
            precoNovo = _aplicarRegra(melhorRegra, precoBase);
            final sinal = melhorRegra.valor >= 0 ? '+' : '';
            final sufixo = melhorRegra.adjustType == 'percentual'
                ? '%'
                : ' R\$';
            origemStr = 'Reajuste $sinal${melhorRegra.valor}$sufixo';
          } else {
            precoNovo = precoBase;
            origemStr = 'Herda lista mãe';
          }
        }

        resultado.add(
          MaterialDraftPreview(
            materialRowId: '',
            productId: pid,
            description: desc,
            listaId: targetListId,
            listaNome: nomeListaFilha,
            tipoLista: 'filha',
            precoAntigo: precoAntigoMae,
            precoNovo: precoNovo,
            origem: origemStr,
            foiEditado: precoNovo != precoAntigoMae,
            cpv: cpvPorPid[pid],
            kgSug: kgSugPorPid[pid],
            ppcNovo: ppcNovoPorPid[pid],
            ppcOferta: ppcOfertaPorPid[pid],
            margemFlatOverride: margemFlatOverridePorPid[pid],
            margemOfertaOverride: margemOfertaOverridePorPid[pid],
            pesoUnidade: pesoUnidadePorPid[pid],
            pesoCaixa: pesoCaixaPorPid[pid],
            dedPct: dedPctPorPid[pid],
            dvPct: dvPctPorPid[pid],
            margemFlat: margemFlatPolitica,
            margemOferta: margemOfertaPolitica,
          ),
        );
      }
    }

    return DraftPreviewResult(
      materiais: resultado,
      resumo: explicacoes.isEmpty
          ? 'Nenhuma modificação detectada neste rascunho.'
          : explicacoes.join('\n'),
    );
  }

  // ── Materiais que NÃO vão para cada lista filha ──────────────────────────

  /// pltyp da lista filha → códigos dos materiais que ela NÃO recebe.
  /// Vazio se não há exclusões ou se a tabela ainda não existe (migração).
  Future<Map<String, Set<String>>> carregarExclusoes(String draftId) async {
    try {
      final rows = await paginar((a, b) => supabase
          .from('price_draft_item_exclusions')
          .select('pltyp, product_id')
          .eq('draft_id', draftId)
          .order('pltyp')
          .order('product_id')
          .range(a, b));
      final out = <String, Set<String>>{};
      for (final r in rows) {
        final l = r['pltyp']?.toString();
        final p = r['product_id']?.toString();
        if (l == null || p == null) continue;
        out.putIfAbsent(l, () => <String>{}).add(p);
      }
      return out;
    } catch (e) {
      if (e is PostgrestException &&
          (e.code == '42P01' ||
              e.code == 'PGRST205' ||
              e.message.contains('price_draft_item_exclusions'))) {
        return {};
      }
      rethrow;
    }
  }

  // ── Listas do rascunho (vigência e status de envio por lista) ─────────────

  static String? _soDigitosData(dynamic v) {
    if (v == null) return null;
    final d = v.toString().replaceAll(RegExp(r'[^0-9]'), '');
    return d.length >= 8 ? d.substring(0, 8) : null;
  }

  static bool _tabelaListasAusente(Object e) =>
      e is PostgrestException &&
      (e.code == '42P01' ||
          e.code == 'PGRST205' ||
          (e.message.contains('price_draft_lists')));

  /// Lista mãe + filhas do rascunho com vigência e status de envio. Cria as
  /// linhas que ainda não existem em `price_draft_lists` (vigência inicial =
  /// a do rascunho). Se a tabela não existe (migração pendente), devolve as
  /// listas só em memória com `persistido: false`.
  Future<DraftListasResult> carregarListasDoDraft(String draftId) async {
    final draft = await supabase
        .from('price_drafts')
        .select('master_list_id, vigencia_datab, vigencia_datbi')
        .eq('id', draftId)
        .single();
    final master = draft['master_list_id']?.toString() ?? '';

    final results = await Future.wait<dynamic>([
      supabase
          .from('price_draft_targets')
          .select('target_list_id')
          .eq('draft_id', draftId),
    ]);
    final targets = results[0] as List;

    // Vigência inicial = a do rascunho (só existe em rascunhos antigos, que
    // exigiam vigência global). Os itens NÃO servem de padrão: sem vigência
    // global eles carregam a vigência antiga do SAP, e a nova é definida por
    // lista na aprovação.
    final datab = _soDigitosData(draft['vigencia_datab']);
    final datbi = _soDigitosData(draft['vigencia_datbi']);

    final ordem = <String>[
      if (master.isNotEmpty) master,
      for (final t in targets)
        if ((t['target_list_id']?.toString() ?? '').isNotEmpty &&
            t['target_list_id'].toString() != master)
          t['target_list_id'].toString(),
    ];

    final nomes = <String, String>{};
    if (ordem.isNotEmpty) {
      final res = await supabase
          .from('price_lists')
          .select('pltyp, ptext')
          .inFilter('pltyp', ordem);
      for (final l in res as List) {
        nomes[l['pltyp'].toString()] = l['ptext']?.toString() ?? '';
      }
    }

    var persistido = true;
    var existentes = <Map<String, dynamic>>[];
    try {
      final res = await supabase
          .from('price_draft_lists')
          .select()
          .eq('draft_id', draftId);
      existentes = (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      if (!_tabelaListasAusente(e)) rethrow;
      persistido = false;
    }
    final porPltyp = {for (final r in existentes) r['pltyp'].toString(): r};

    if (persistido) {
      final novas = [
        for (final p in ordem)
          if (!porPltyp.containsKey(p))
            {
              'draft_id': draftId,
              'pltyp': p,
              'is_master': p == master,
              'datab': datab,
              'datbi': datbi,
              'status': 'pending',
            },
      ];
      if (novas.isNotEmpty) {
        await supabase.from('price_draft_lists').insert(novas);
        for (final n in novas) {
          porPltyp[n['pltyp'] as String] = n;
        }
      }
    }

    final listas = [
      for (final p in ordem)
        DraftLista(
          pltyp: p,
          isMaster: p == master,
          nome: (nomes[p] ?? '').isEmpty ? p : nomes[p]!,
          datab: _soDigitosData(porPltyp[p]?['datab']) ?? datab,
          datbi: _soDigitosData(porPltyp[p]?['datbi']) ?? datbi,
          status: porPltyp[p]?['status']?.toString() ?? 'pending',
          sentAt: DateTime.tryParse(porPltyp[p]?['sent_at']?.toString() ?? ''),
          sentByEmail: porPltyp[p]?['sent_by_email']?.toString(),
        ),
    ];
    // Quantos materiais cada lista recebe (para o resumo na Aprovação).
    try {
      final itensRes = await paginar((a, b) => supabase
          .from('price_draft_items')
          .select('product_id')
          .eq('draft_id', draftId)
          .order('product_id')
          .range(a, b));
      final total = itensRes.length;
      final exclusoes = await carregarExclusoes(draftId);
      for (final l in listas) {
        l.totalMateriais = total;
        l.excluidos = l.isMaster ? <String>{} : (exclusoes[l.pltyp] ?? <String>{});
      }
    } catch (_) {
      // só informativo — não impede abrir o rascunho
    }
    return DraftListasResult(listas: listas, persistido: persistido);
  }

  /// Grava a vigência (AAAAMMDD) das listas [pltyps] do rascunho. Só as listas
  /// ainda pendentes são alteradas (as já enviadas ao SAP não mudam).
  Future<void> salvarVigenciaListas(
    String draftId,
    List<String> pltyps, {
    required String datab,
    required String datbi,
  }) async {
    if (pltyps.isEmpty) return;
    await supabase
        .from('price_draft_lists')
        .update({'datab': datab, 'datbi': datbi})
        .eq('draft_id', draftId)
        .eq('status', 'pending')
        .inFilter('pltyp', pltyps);
  }

  /// Publica o rascunho no SAP.
  ///
  /// [pltyps] = listas a enviar; null = todas que ainda não foram enviadas.
  /// As demais ficam 'pending' e o rascunho continua aguardando aprovação.
  /// Cada lista vai com a própria vigência (`price_draft_lists`).
  Future<int> applyDraft(String draftId, {List<String>? pltyps}) async {
    final itemsRes = await supabase
        .from('price_draft_items')
        .select(
          'product_id, new_price, datab, datbi, konwa, kmein, krech, mxwrt, gkwrt, sap_status, ppc_novo',
        )
        .eq('draft_id', draftId);

    final items = itemsRes as List;
    if (items.isEmpty) {
      throw Exception('Nenhum item encontrado neste rascunho.');
    }

    final listasRes = await carregarListasDoDraft(draftId);
    if (listasRes.listas.isEmpty) {
      throw Exception('Draft sem lista mãe (pltyp) definida.');
    }

    final aEnviar = listasRes.listas
        .where(
          (l) =>
              !l.enviada && (pltyps == null || pltyps.contains(l.pltyp)),
        )
        .toList();
    if (aEnviar.isEmpty) {
      throw Exception('Nenhuma lista pendente selecionada para enviar.');
    }
    final semVigencia = listasRes.persistido
        ? aEnviar.where((l) => !l.temVigencia).toList()
        : <DraftLista>[]; // sem a tabela por lista, usa a vigência dos itens
    if (semVigencia.isNotEmpty) {
      throw Exception(
        'Defina a vigência das listas: '
        '${semVigencia.map((l) => l.nome).join(', ')}.',
      );
    }

    return _publicar(
      draftId: draftId,
      items: items,
      listas: listasRes.listas,
      aEnviar: aEnviar,
      persistido: listasRes.persistido,
    );
  }

  /// Reenvia ao SAP apenas os materiais deste draft marcados com sap_erro
  /// (falharam numa aprovação anterior) — não recria nem reenvia os itens
  /// que já foram confirmados. Só vai para listas que JÁ foram publicadas;
  /// listas ainda pendentes de aprovação nunca recebem preço por aqui.
  Future<int> reprocessarFalhas(String draftId) async {
    final itemsRes = await supabase
        .from('price_draft_items')
        .select(
          'product_id, new_price, datab, datbi, konwa, kmein, krech, mxwrt, gkwrt, sap_status, ppc_novo',
        )
        .eq('draft_id', draftId)
        .not('sap_erro', 'is', null);

    final items = itemsRes as List;
    if (items.isEmpty) {
      throw Exception(
        'Nenhum material pendente de reprocessamento neste rascunho.',
      );
    }

    final listasRes = await carregarListasDoDraft(draftId);
    if (listasRes.listas.isEmpty) {
      throw Exception('Draft sem lista mãe (pltyp) definida.');
    }

    final aEnviar = listasRes.persistido
        ? listasRes.listas.where((l) => l.foiPublicada).toList()
        : listasRes.listas;
    if (aEnviar.isEmpty) {
      throw Exception('Nenhuma lista publicada para reprocessar.');
    }

    return _publicar(
      draftId: draftId,
      items: items,
      listas: listasRes.listas,
      aEnviar: aEnviar,
      persistido: listasRes.persistido,
      reprocesso: true,
    );
  }

  /// Envia [items] para cada lista de [aEnviar] (com a vigência dela),
  /// registra o resultado por lista e atualiza o status do rascunho.
  Future<int> _publicar({
    required String draftId,
    required List items,
    required List<DraftLista> listas,
    required List<DraftLista> aEnviar,
    required bool persistido,
    bool reprocesso = false,
  }) async {
    final excecoesRes = await supabase
        .from('price_draft_exceptions')
        .select(
          'target_list_id, level, adjust_type, value, cluster_id, material_id',
        )
        .eq('draft_id', draftId);

    final pids = items.map((i) => i['product_id']?.toString() ?? '').toList();
    final clusterMap = await _clusterMapForProducts(pids);
    final exclusoes = await carregarExclusoes(draftId);

    // Materiais de cada lista: a mãe recebe todos; cada filha, todos menos os
    // que foram escolhidos para ficar de fora dela.
    List itensDaLista(DraftLista l) {
      final fora = l.isMaster ? null : exclusoes[l.pltyp];
      if (fora == null || fora.isEmpty) return items;
      return items
          .where((i) => !fora.contains(i['product_id']?.toString()))
          .toList();
    }

    final falhasPorLista = <String, List<Map<String, dynamic>>>{};
    Object? erroEnvio;
    StackTrace? erroTrace;

    for (final l in aEnviar) {
      final regras = l.isMaster
          ? const []
          : (excecoesRes as List)
                .where((e) => e['target_list_id']?.toString() == l.pltyp)
                .toList();
      final itensLista = itensDaLista(l);
      if (itensLista.isEmpty) {
        // Nenhum material para esta lista: nada a enviar ao SAP.
        falhasPorLista[l.pltyp] = [];
        continue;
      }
      try {
        falhasPorLista[l.pltyp] = await _enviarPayload(
          l.pltyp,
          _montarSapItems(itensLista, clusterMap, regras,
              datab: l.datab, datbi: l.datbi),
        );
      } catch (e, st) {
        // Falha de comunicação nesta lista: para aqui. As listas já
        // processadas são registradas abaixo; esta e as seguintes seguem
        // pendentes.
        erroEnvio = e;
        erroTrace = st;
        break;
      }
    }

    final falhas = [for (final f in falhasPorLista.values) ...f];
    final falhaMatnrs = falhas
        .map((f) => f['matnr']?.toString())
        .whereType<String>()
        .toSet();

    // Status por lista (só das que foram de fato processadas).
    final email = supabase.auth.currentUser?.email;
    for (final entry in falhasPorLista.entries) {
      final l = aEnviar.firstWhere((x) => x.pltyp == entry.key);
      l.status = entry.value.isEmpty ? 'sent' : 'error';
      l.sentAt = DateTime.now();
      l.sentByEmail = email;
      if (persistido) {
        await supabase
            .from('price_draft_lists')
            .update({
              'status': l.status,
              'sent_at': l.sentAt!.toIso8601String(),
              'sent_by_email': email,
            })
            .eq('draft_id', draftId)
            .eq('pltyp', l.pltyp);
      }
    }

    // sap_erro nos itens: só limpa se nenhuma lista continua com erro.
    final aindaComErro = listas.any((l) => l.comErro);
    await _marcarFalhasNosItens(
      draftId,
      items,
      falhaMatnrs,
      falhas,
      limparOk: !aindaComErro,
    );

    // PPC histórico: só das listas enviadas, com a vigência de cada uma.
    final porLista = <MapEntry<DraftLista, List>>[];
    for (final entry in falhasPorLista.entries) {
      final l = aEnviar.firstWhere((x) => x.pltyp == entry.key);
      final matnrsComFalha = entry.value
          .map((f) => f['matnr']?.toString())
          .whereType<String>()
          .toSet();
      final ok = itensDaLista(l)
          .where((i) => !matnrsComFalha.contains(i['product_id']?.toString()))
          .toList();
      if (ok.isNotEmpty) porLista.add(MapEntry(l, ok));
    }
    if (porLista.isNotEmpty) {
      await _gravarPpcHistorico(draftId, porLista);
    }

    // O rascunho só vira 'approved' quando não resta lista pendente.
    if (!reprocesso && (!persistido || !listas.any((l) => l.pendente))) {
      await supabase
          .from('price_drafts')
          .update({'status': 'approved'})
          .eq('id', draftId);
    }

    if (erroEnvio != null) {
      Error.throwWithStackTrace(erroEnvio, erroTrace ?? StackTrace.current);
    }
    if (falhas.isNotEmpty) {
      throw SapPushFalhasException(total: items.length, falhas: falhas);
    }

    return items.length;
  }

  /// Atualiza price_draft_items.sap_erro: limpa nos itens que agora foram
  /// confirmados e grava a mensagem nos que continuam falhando.
  Future<void> _marcarFalhasNosItens(
    String draftId,
    List items,
    Set<String> falhaMatnrs,
    List<Map<String, dynamic>> falhas, {
    bool limparOk = true,
  }) async {
    final erroPorMatnr = <String, String>{
      for (final f in falhas)
        (f['matnr']?.toString() ?? ''): (f['erro']?.toString() ??
            'motivo desconhecido'),
    };

    final okIds = items
        .map((i) => i['product_id']?.toString() ?? '')
        .where((pid) => pid.isNotEmpty && !falhaMatnrs.contains(pid))
        .toList();

    if (limparOk && okIds.isNotEmpty) {
      await supabase
          .from('price_draft_items')
          .update({'sap_erro': null})
          .eq('draft_id', draftId)
          .inFilter('product_id', okIds);
    }

    for (final pid in falhaMatnrs) {
      if (pid.isEmpty) continue;
      await supabase
          .from('price_draft_items')
          .update({'sap_erro': erroPorMatnr[pid]})
          .eq('draft_id', draftId)
          .eq('product_id', pid);
    }
  }

  /// Congela o PPC usado neste ciclo — vira o "PPC Atual" na próxima vez
  /// que essa lista for aberta na Gestão de Preços. Grava só para as listas
  /// efetivamente enviadas, com a vigência de cada uma.
  Future<void> _gravarPpcHistorico(
    String draftId,
    List<MapEntry<DraftLista, List>> porLista,
  ) async {
    final rows = <Map<String, dynamic>>[];
    for (final entry in porLista) {
      final lista = entry.key;
      for (final item in entry.value) {
        final ppcNovo = _toDouble(item['ppc_novo']);
        if (ppcNovo == null) continue;
        final pid = item['product_id']?.toString();
        if (pid == null) continue;
        rows.add({
          'pltyp': lista.pltyp,
          'product_code': pid,
          'ppc': ppcNovo,
          'vigencia_datab': lista.datab ?? item['datab'],
          'vigencia_datbi': lista.datbi ?? item['datbi'],
          'draft_id': draftId,
        });
      }
    }

    if (rows.isEmpty) return;
    await supabase
        .from('ppc_historico')
        .upsert(rows, onConflict: 'pltyp,product_code');
  }

  List<Map<String, dynamic>> _montarSapItems(
    List items,
    Map<String, String> clusterMap,
    List regras, {
    String? datab, // vigência da lista (AAAAMMDD); null = a do item
    String? datbi,
  }) {
    return items.map((item) {
      final matnr = item['product_id']?.toString() ?? '';
      double kbetr = _toDouble(item['new_price']) ?? 0.0;

      _RegraMatch? melhor;
      if (regras.isNotEmpty) {
        melhor = _melhorRegra(
          regras,
          productId: matnr,
          clusterId: clusterMap[matnr],
        );
        if (melhor != null) kbetr = _aplicarRegra(melhor, kbetr);
      }

      // Evita ruído de ponto flutuante (ex.: 140.06000000000001) antes de
      // enviar ao SAP.
      kbetr = double.parse(kbetr.toStringAsFixed(2));

      // MXWRT (valor inferior) e GKWRT (valor superior) são os limites da
      // condição de preço no SAP (tela VK11). Editáveis manualmente por
      // material (botão "Limites SAP" na tela de Preços) — quando nenhum dos
      // dois é informado, vão como 0,00 (sem limite). Informando só um, o
      // outro assume o KBETR (ver abaixo).
      //
      // Os limites são calculados sobre o preço BASE do rascunho. Em lista
      // filha com exceção de política, o KBETR recebe a regra (% ou valor
      // fixo); os limites precisam receber a MESMA regra, senão o KBETR
      // passa do GKWRT (ex.: KBETR 166,49 com GKWRT 157,50). Limite 0 (sem
      // limite) continua 0.
      double limite(dynamic v) {
        final base = _toDouble(v) ?? 0.0;
        if (base <= 0 || melhor == null) return base;
        return double.parse(_aplicarRegra(melhor, base).toStringAsFixed(2));
      }

      var mxwrt = limite(item['mxwrt']);
      var gkwrt = limite(item['gkwrt']);

      // O SAP rejeita a condição com só um limite preenchido (VK023). Se o
      // usuário informou apenas um lado, o outro assume o valor padrão: o
      // próprio preço enviado (KBETR já com a exceção da lista).
      if (mxwrt > 0 && gkwrt <= 0) {
        gkwrt = kbetr;
      } else if (gkwrt > 0 && mxwrt <= 0) {
        mxwrt = kbetr;
      }

      return {
        'MATNR': matnr,
        'KBETR': kbetr,
        'KONWA': item['konwa']?.toString() ?? 'BRL',
        'KMEIN': item['kmein']?.toString() ?? 'KG',
        'KRECH': item['krech']?.toString() ?? 'C',
        'DATAB': (datab != null && datab.isNotEmpty)
            ? datab
            : (item['datab']?.toString() ?? ''),
        'DATBI': (datbi != null && datbi.isNotEmpty)
            ? datbi
            : (item['datbi']?.toString() ?? ''),
        'MXWRT': mxwrt,
        'GKWRT': gkwrt,
        'STATUS': item['sap_status']?.toString() ?? '',
      };
    }).toList();
  }

  /// Envia o payload ao SAP e retorna a lista de falhas por material que o
  /// ABAP reportou (BDC não confirmada) — vazia quando tudo foi gravado.
  Future<List<Map<String, dynamic>>> _enviarPayload(
    String pltyp,
    List<Map<String, dynamic>> sapItems,
  ) async {
    final payload = {'pltyp': pltyp, 'items': sapItems};
    final res = await supabase.functions.invoke(
      'push-sap-prices',
      body: payload,
    );
    if (res.status != 200) {
      throw Exception(
        'Falha ao enviar lista $pltyp (${res.status}): ${res.data}',
      );
    }

    final data = res.data;
    final falhasRaw = data is Map ? data['falhas'] : null;
    if (falhasRaw is! List || falhasRaw.isEmpty) return [];

    return falhasRaw
        .whereType<Map>()
        .map(
          (f) => {
            'pltyp': pltyp,
            // Normaliza zeros à esquerda: o product_id salvo no draft nunca
            // tem (ver sap_sync_service._mapEntriesToMateriais), mas o SAP
            // pode devolver o matnr convertido via CONVERSION_EXIT_ALPHA_INPUT
            // (ex.: "000000000000300575"). Sem isso, a falha nunca casa com
            // o item do draft e sap_erro nunca é gravado.
            'matnr': _semZerosEsquerda(f['matnr']?.toString() ?? '?'),
            'erro': f['erro']?.toString() ?? 'motivo desconhecido',
          },
        )
        .toList();
  }

  String _semZerosEsquerda(String matnr) {
    final semZeros = matnr.replaceFirst(RegExp(r'^0+(?=.)'), '');
    return semZeros.isEmpty ? matnr : semZeros;
  }

  Future<Map<String, String>> _clusterMapForProducts(List<String> codes) async {
    if (codes.isEmpty) return {};
    final prodRes = await emBlocos(
      codes,
      (parte) => paginar((a, b) => supabase
          .from('products')
          .select('code, pricing_cluster_id')
          .inFilter('code', parte)
          .order('code')
          .range(a, b)),
    );

    final map = <String, String>{};
    for (final row in prodRes as List) {
      final code = row['code']?.toString();
      final clusterId = row['pricing_cluster_id']?.toString();
      if (code != null && clusterId != null) map[code] = clusterId;
    }
    return map;
  }

  _RegraMatch? _melhorRegra(
    List<dynamic> regras, {
    required String productId,
    required String? clusterId,
  }) {
    _RegraMatch? melhor;
    for (final regra in regras) {
      final level = regra['level']?.toString() ?? '';
      final adjustType = regra['adjust_type']?.toString() ?? 'percentual';
      final valor = _toDouble(regra['value']) ?? 0.0;
      final regraClusterId = regra['cluster_id']?.toString();
      final materialId = regra['material_id']?.toString();

      int prioridade = 0;
      var aplica = false;

      if (level == 'specific_material' && materialId == productId) {
        prioridade = 3;
        aplica = true;
      } else if (level == 'material_group' &&
          regraClusterId != null &&
          clusterId == regraClusterId) {
        prioridade = 2;
        aplica = true;
      } else if (level == 'full_table') {
        prioridade = 1;
        aplica = true;
      }

      if (aplica && (melhor == null || prioridade > melhor.prioridade)) {
        melhor = _RegraMatch(
          prioridade: prioridade,
          adjustType: adjustType,
          valor: valor,
        );
      }
    }
    return melhor;
  }

  double _aplicarRegra(_RegraMatch regra, double base) {
    if (regra.adjustType == 'percentual') {
      return base * (1 + (regra.valor / 100));
    }
    return base + regra.valor;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
