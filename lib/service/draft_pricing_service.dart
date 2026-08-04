import 'package:pole_price/models/material_draft_preview.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        supabase.from('products').select('code, name').inFilter('code', pids),
        supabase
            .from('materials')
            .select('material_code, peso_unidade, peso_caixa')
            .inFilter('material_code', pids),
        supabase
            .from('product_costs')
            .select('product_code, ded_pct, dv_pct, period')
            .inFilter('product_code', pids),
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

  Future<int> applyDraft(String draftId) async {
    final itemsRes = await supabase
        .from('price_draft_items')
        .select(
          'product_id, new_price, datab, datbi, konwa, kmein, krech, mxwrt, sap_status, ppc_novo',
        )
        .eq('draft_id', draftId);

    final items = itemsRes as List;
    if (items.isEmpty)
      throw Exception('Nenhum item encontrado neste rascunho.');

    final draftData = await supabase
        .from('price_drafts')
        .select('master_list_id')
        .eq('id', draftId)
        .single();

    final String pltyp = draftData['master_list_id']?.toString() ?? '';
    if (pltyp.isEmpty) throw Exception('Draft sem lista mãe (pltyp) definida.');

    final results = await Future.wait([
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

    final targetsRes = results[0] as List;
    final excecoesRes = results[1] as List;

    final pids = items.map((i) => i['product_id']?.toString() ?? '').toList();
    final clusterMap = await _clusterMapForProducts(pids);

    // Envia lista mãe
    await _enviarPayload(pltyp, _montarSapItems(items, clusterMap, []));

    // Envia cada lista filha com regras aplicadas
    for (final target in targetsRes) {
      final filhaPltyp = target['target_list_id']?.toString() ?? '';
      if (filhaPltyp.isEmpty) continue;

      final regrasFilha = excecoesRes
          .where((e) => e['target_list_id']?.toString() == filhaPltyp)
          .toList();

      await _enviarPayload(
        filhaPltyp,
        _montarSapItems(items, clusterMap, regrasFilha),
      );
    }

    await _gravarPpcHistorico(draftId, pltyp, targetsRes, items);

    await supabase
        .from('price_drafts')
        .update({'status': 'approved'})
        .eq('id', draftId);

    return items.length;
  }

  /// Congela o PPC usado neste ciclo — vira o "PPC Atual" na próxima vez
  /// que essa lista (mãe e filhas) for aberta na Gestão de Preços.
  Future<void> _gravarPpcHistorico(
    String draftId,
    String pltyp,
    List targetsRes,
    List items,
  ) async {
    final pltyps = <String>{
      pltyp,
      ...targetsRes.map((t) => t['target_list_id']?.toString() ?? ''),
    }..removeWhere((p) => p.isEmpty);

    final rows = <Map<String, dynamic>>[];
    for (final item in items) {
      final ppcNovo = _toDouble(item['ppc_novo']);
      if (ppcNovo == null) continue;
      final pid = item['product_id']?.toString();
      if (pid == null) continue;
      for (final p in pltyps) {
        rows.add({
          'pltyp': p,
          'product_code': pid,
          'ppc': ppcNovo,
          'vigencia_datab': item['datab'],
          'vigencia_datbi': item['datbi'],
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
    List regras,
  ) {
    return items.map((item) {
      final matnr = item['product_id']?.toString() ?? '';
      double kbetr = _toDouble(item['new_price']) ?? 0.0;

      if (regras.isNotEmpty) {
        final melhor = _melhorRegra(
          regras,
          productId: matnr,
          clusterId: clusterMap[matnr],
        );
        if (melhor != null) kbetr = _aplicarRegra(melhor, kbetr);
      }

      // Evita ruído de ponto flutuante (ex.: 140.06000000000001) antes de
      // enviar ao SAP.
      kbetr = double.parse(kbetr.toStringAsFixed(2));

      return {
        'MATNR': matnr,
        'KBETR': kbetr,
        'KONWA': item['konwa']?.toString() ?? 'BRL',
        'KMEIN': item['kmein']?.toString() ?? 'KG',
        'KRECH': item['krech']?.toString() ?? 'C',
        'DATAB': item['datab']?.toString() ?? '',
        'DATBI': item['datbi']?.toString() ?? '',
        'MXWRT': _toDouble(item['mxwrt']) ?? 0.0,
        'STATUS': item['sap_status']?.toString() ?? '',
      };
    }).toList();
  }

  Future<void> _enviarPayload(
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
  }

  Future<Map<String, String>> _clusterMapForProducts(List<String> codes) async {
    if (codes.isEmpty) return {};
    final prodRes = await supabase
        .from('products')
        .select('code, pricing_cluster_id')
        .inFilter('code', codes);

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
