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
          .select('product_id, old_price, new_price, datab, datbi, origem_material')
          .eq('draft_id', draftId),
      supabase
          .from('price_draft_targets')
          .select('target_list_id')
          .eq('draft_id', draftId),
      supabase
          .from('price_draft_exceptions')
          .select('target_list_id, level, adjust_type, value, cluster_id, material_id')
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
    final Map<String, String> descricaoPorPid = {}; // preenchido abaixo se disponível

    for (final item in itensRes) {
      final pid = item['product_id']?.toString();
      if (pid == null) continue;
      final np = _toDouble(item['new_price']);
      final op = _toDouble(item['old_price']);
      if (np != null) precoNovoPorPid[pid] = np;
      if (op != null) precoAntigoPorPid[pid] = op;
    }

    // Busca descrições dos produtos editados (products table, não materials)
    if (precoNovoPorPid.isNotEmpty) {
      final pids = precoNovoPorPid.keys.toList();
      final prodsRes = await supabase
          .from('products')
          .select('code, name')
          .inFilter('code', pids);
      for (final p in prodsRes as List) {
        final code = p['code']?.toString();
        final name = p['name']?.toString();
        if (code != null && name != null) descricaoPorPid[code] = name;
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
          foiEditado: true,
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
    final clusterMap = await _clusterMapForProducts(precoNovoPorPid.keys.toList());

    // ── 7. Processa cada lista filha ─────────────────────────────────────
    for (final targetListId in targetIds) {
      final nomeListaFilha = nomesPorPltyp[targetListId] ?? targetListId;

      final regrasFilha = excecoesRes
          .where((e) => e['target_list_id']?.toString() == targetListId)
          .toList();

      if (regrasFilha.isEmpty) {
        explicacoes.add('• Lista filha "$nomeListaFilha": herda preços da lista mãe.');
      } else {
        final niveisTxt = regrasFilha.map((r) {
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
        }).join(', ');
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
            final sufixo = melhorRegra.adjustType == 'percentual' ? '%' : ' R\$';
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
            foiEditado: true,
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

  /// Publica preços aprovados de volta ao SAP via edge function,
  /// e marca o draft como aprovado no Supabase.
  Future<int> applyDraft(String draftId) async {
    final preview = await buildPreview(draftId);

    final alterados = preview.materiais
        .where((m) => m.foiEditado)
        .toList();

    if (alterados.isEmpty) {
      throw Exception('Nenhum preço foi alterado neste rascunho.');
    }

    // Agrupa por lista para envio
    final Map<String, List<MaterialDraftPreview>> porLista = {};
    for (final m in alterados) {
      porLista.putIfAbsent(m.listaId, () => []).add(m);
    }

    // Salva os novos preços em price_draft_items para o push_sap_prices usar
    // (o applyDraft não grava mais em materials — envia ao SAP na aprovação)
    await supabase
        .from('price_drafts')
        .update({'status': 'approved'})
        .eq('id', draftId);

    return alterados.length;
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