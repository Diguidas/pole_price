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

/// Centraliza cálculo de preview e aplicação de drafts (lista mãe + filhas).
class DraftPricingService {
  final SupabaseClient supabase;

  DraftPricingService(this.supabase);

  Future<DraftPreviewResult> buildPreview(String draftId) async {
    // ── 1. Busca dados do draft + nome da lista mãe ──────────────────────
    final draftData = await supabase
        .from('price_drafts')
        .select('master_list_id, price_lists!master_list_id(description)')
        .eq('id', draftId)
        .single();

    final String? masterListId = draftData['master_list_id'] as String?;
    final priceList = draftData['price_lists'] as Map<String, dynamic>?;
    final String nomeListaMae =
        priceList?['description']?.toString() ?? 'Lista Mãe';

    // ── 2. Busca itens editados, targets e exceções em paralelo ──────────
    final futures = await Future.wait<dynamic>([
      supabase
          .from('price_draft_items')
          .select('product_id, old_price, new_price') // old_price sempre buscado
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

    // ── 3. Monta mapas de preços editados E preços antigos da lista mãe ──
    //
    // CORREÇÃO CRÍTICA: o precoAntigo NÃO pode vir de materials.price porque
    // após applyDraft o banco já tem o preço novo. O old_price salvo em
    // price_draft_items no momento do saveDraft é a fonte correta.
    final Map<String, double> precoEditadoMae = {};  // product_id → new_price
    final Map<String, double> precoAntigoMae = {};   // product_id → old_price
    for (final item in itensRes) {
      final pid = item['product_id']?.toString();
      final np = _toDouble(item['new_price']);
      final op = _toDouble(item['old_price']);
      if (pid != null && np != null) precoEditadoMae[pid] = np;
      if (pid != null && op != null) precoAntigoMae[pid] = op;
    }

    final resultado = <MaterialDraftPreview>[];
    final explicacoes = <String>[];
    final Map<String, double> precoPropostoMae = {};

    // ── 4. Processa lista mãe ────────────────────────────────────────────
    if (masterListId != null) {
      final matsMae = await supabase
          .from('materials')
          .select('id, product_id, description, price')
          .eq('price_list_id', masterListId);

      for (final mat in matsMae as List) {
        final rowId = mat['id']?.toString() ?? '';
        final pid = mat['product_id']?.toString() ?? '';
        final desc = mat['description']?.toString() ?? 'Sem descrição';
        final precoNoBanco = _toDouble(mat['price']) ?? 0.0;
        final precoNovo = precoEditadoMae[pid] ?? precoNoBanco;
        final foiEditado = precoEditadoMae.containsKey(pid);

        // Usa old_price salvo no draft. Se não houver (material não editado),
        // o preço do banco é confiável porque não foi alterado pelo applyDraft.
        final precoAntigo = foiEditado
            ? (precoAntigoMae[pid] ?? precoNoBanco)
            : precoNoBanco;

        precoPropostoMae[pid] = precoNovo;

        resultado.add(
          MaterialDraftPreview(
            materialRowId: rowId,
            productId: pid,
            description: desc,
            listaId: masterListId,
            listaNome: nomeListaMae,
            tipoLista: 'mae',
            precoAntigo: precoAntigo,   // ← agora vem do old_price salvo
            precoNovo: precoNovo,
            origem: foiEditado ? 'Ajuste manual' : 'Sem alteração',
            foiEditado: foiEditado,
          ),
        );
      }

      if (precoEditadoMae.isNotEmpty) {
        explicacoes.add(
          '• ${precoEditadoMae.length} material(is) editado(s) na lista mãe "$nomeListaMae".',
        );
      }
    }

    if (targetsRes.isEmpty) {
      return DraftPreviewResult(
        materiais: resultado,
        resumo: explicacoes.isEmpty
            ? 'Nenhuma regra ou modificação detectada neste rascunho.'
            : explicacoes.join('\n'),
      );
    }

    // ── 5. Busca nomes de TODAS as listas filhas de uma vez (era N+1) ────
    final targetIds = targetsRes
        .map((t) => t['target_list_id']?.toString())
        .whereType<String>()
        .toList();

    final listaNamesRes = await supabase
        .from('price_lists')
        .select('id, description')
        .inFilter('id', targetIds);

    final Map<String, String> nomesPorListaId = {
      for (final l in listaNamesRes as List)
        if (l['id'] != null)
          l['id'].toString(): l['description']?.toString() ?? 'Lista Filha',
    };

    // ── 6. Busca materiais de TODAS as listas filhas de uma vez ──────────
    final matsFuturas = await Future.wait(
      targetIds.map(
        (id) => supabase
            .from('materials')
            .select('id, product_id, description, price')
            .eq('price_list_id', id),
      ),
    );

    // Coleta todos os product_ids das filhas para buscar clusters em batch
    final Set<String> todosPids = {};
    for (final matsFilha in matsFuturas) {
      for (final mat in matsFilha as List) {
        final pid = mat['product_id']?.toString();
        if (pid != null) todosPids.add(pid);
      }
    }

    // ── 7. Busca cluster de todos os produtos das filhas em uma query ────
    final clusterMapGlobal = await _clusterMapForProducts(todosPids.toList());

    // ── 8. Processa cada lista filha ─────────────────────────────────────
    for (var i = 0; i < targetIds.length; i++) {
      final targetListId = targetIds[i];
      final nomeListaFilha = nomesPorListaId[targetListId] ?? 'Lista Filha';
      final matsFilha = matsFuturas[i] as List;

      final regrasFilha = (excecoesRes)
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

      for (final mat in matsFilha) {
        final rowId = mat['id']?.toString() ?? '';
        final pid = mat['product_id']?.toString() ?? '';
        final desc = mat['description']?.toString() ?? 'Sem descrição';
        final precoAtual = _toDouble(mat['price']) ?? 0.0;
        final clusterIdMat = clusterMapGlobal[pid];

        // Para listas filhas o precoAtual do banco ainda é confiável como
        // "preço anterior", pois applyDraft também atualiza as filhas.
        // A referência base para calcular o novo preço é o proposto na mãe.
        final basePreco = precoPropostoMae[pid] ?? precoAtual;
        double precoNovo = precoAtual;
        String origemStr = 'Sem alteração';
        bool foiAlterado = false;

        if (regrasFilha.isEmpty) {
          if (precoPropostoMae.containsKey(pid)) {
            precoNovo = precoPropostoMae[pid]!;
            origemStr = 'Herda lista mãe';
            foiAlterado = precoNovo != precoAtual;
          }
        } else {
          final melhorRegra = _melhorRegra(
            regrasFilha,
            productId: pid,
            clusterId: clusterIdMat,
          );

          if (melhorRegra != null) {
            precoNovo = _aplicarRegra(melhorRegra, basePreco);
            final sinal = melhorRegra.valor >= 0 ? '+' : '';
            final sufixo = melhorRegra.adjustType == 'percentual'
                ? '%'
                : ' R\$';
            origemStr = 'Reajuste $sinal${melhorRegra.valor}$sufixo';
            foiAlterado = precoNovo != precoAtual;
          } else if (precoPropostoMae.containsKey(pid)) {
            precoNovo = precoPropostoMae[pid]!;
            origemStr = 'Herda lista mãe';
            foiAlterado = precoNovo != precoAtual;
          }
        }

        resultado.add(
          MaterialDraftPreview(
            materialRowId: rowId,
            productId: pid,
            description: desc,
            listaId: targetListId,
            listaNome: nomeListaFilha,
            tipoLista: 'filha',
            precoAntigo: precoAtual,
            precoNovo: precoNovo,
            origem: origemStr,
            foiEditado: foiAlterado,
          ),
        );
      }
    }

    return DraftPreviewResult(
      materiais: resultado,
      resumo: explicacoes.isEmpty
          ? 'Nenhuma regra ou modificação detectada neste rascunho.'
          : explicacoes.join('\n'),
    );
  }

  /// Publica preços em `materials.price` e marca draft approved.
  Future<int> applyDraft(String draftId) async {
    final draftMeta = await supabase
        .from('price_drafts')
        .select('master_list_id')
        .eq('id', draftId)
        .single();
    final masterListId = draftMeta['master_list_id']?.toString();

    final preview = await buildPreview(draftId);

    // Separa materiais que realmente mudaram de preço
    final alterados = preview.materiais
        .where((m) => (m.precoNovo - m.precoAntigo).abs() >= 0.001)
        .where((m) => m.materialRowId.isNotEmpty)
        .toList();

    if (alterados.isEmpty) {
      throw Exception('Nenhum preço foi alterado neste rascunho.');
    }

    // Agrupa por lista para fazer upserts em batch por lista
    final Map<String, List<MaterialDraftPreview>> porLista = {};
    for (final m in alterados) {
      porLista.putIfAbsent(m.listaId, () => []).add(m);
    }

    final falhas = <String>[];
    var atualizados = 0;

    for (final entry in porLista.entries) {
      final listaId = entry.key;
      final materiais = entry.value;

      final rows = materiais
          .map(
            (m) => {
              'id': m.materialRowId,
              'product_id': m.productId.trim(),
              'description': m.description,
              'price': m.precoNovo,
              'price_list_id': m.listaId,
              'is_fixed': true,
            },
          )
          .toList();

      try {
        await supabase.from('materials').upsert(rows);
        atualizados += materiais.length;
      } catch (e) {
        for (final m in materiais) {
          falhas.add('${m.productId} em "${m.listaNome}": $e');
        }
      }
    }

    if (atualizados == 0) {
      final detalhe = falhas.isNotEmpty ? '\n${falhas.take(8).join('\n')}' : '';
      throw Exception('Nenhum preço foi publicado no Supabase.$detalhe');
    }

    if (falhas.isNotEmpty) {
      throw Exception(
        'Publicação incompleta ($atualizados ok, ${falhas.length} falha(s)). '
        'O rascunho permanece pendente.\n${falhas.take(8).join('\n')}',
      );
    }

    await supabase
        .from('price_drafts')
        .update({'status': 'approved'})
        .eq('id', draftId);

    return atualizados;
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