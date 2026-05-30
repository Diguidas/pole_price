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
    final draftData = await supabase
        .from('price_drafts')
        .select('master_list_id, price_lists!master_list_id(description)')
        .eq('id', draftId)
        .single();

    final String? masterListId = draftData['master_list_id'] as String?;
    final priceList = draftData['price_lists'] as Map<String, dynamic>?;
    final String nomeListaMae =
        priceList?['description']?.toString() ?? 'Lista Mãe';

    final itensRes = await supabase
        .from('price_draft_items')
        .select('product_id, old_price, new_price')
        .eq('draft_id', draftId);

    final Map<String, double> precoEditadoMae = {};
    for (final item in itensRes as List) {
      final pid = item['product_id']?.toString();
      final np = _toDouble(item['new_price']);
      if (pid != null && np != null) precoEditadoMae[pid] = np;
    }

    final resultado = <MaterialDraftPreview>[];
    final explicacoes = <String>[];
    final Map<String, double> precoPropostoMae = {};

    if (masterListId != null) {
      final matsMae = await supabase
          .from('materials')
          .select('id, product_id, description, price')
          .eq('price_list_id', masterListId);

      for (final mat in matsMae as List) {
        final rowId = mat['id']?.toString() ?? '';
        final pid = mat['product_id']?.toString() ?? '';
        final desc = mat['description']?.toString() ?? 'Sem descrição';
        final precoAtual = _toDouble(mat['price']) ?? 0.0;
        final precoNovo = precoEditadoMae[pid] ?? precoAtual;
        final foiEditado = precoEditadoMae.containsKey(pid);

        precoPropostoMae[pid] = precoNovo;

        resultado.add(MaterialDraftPreview(
          materialRowId: rowId,
          productId: pid,
          description: desc,
          listaId: masterListId,
          listaNome: nomeListaMae,
          tipoLista: 'mae',
          precoAntigo: precoAtual,
          precoNovo: precoNovo,
          origem: foiEditado ? 'Ajuste manual' : 'Sem alteração',
          foiEditado: foiEditado,
        ));
      }

      if (precoEditadoMae.isNotEmpty) {
        explicacoes.add(
          '• ${precoEditadoMae.length} material(is) editado(s) na lista mãe "$nomeListaMae".',
        );
      }
    }

    final targetsRes = await supabase
        .from('price_draft_targets')
        .select('target_list_id')
        .eq('draft_id', draftId);

    final excecoesRes = await supabase
        .from('price_draft_exceptions')
        .select(
          'target_list_id, level, adjust_type, value, cluster_id, material_id',
        )
        .eq('draft_id', draftId);

    for (final target in targetsRes as List) {
      final targetListId = target['target_list_id']?.toString();
      if (targetListId == null) continue;

      String nomeListaFilha = 'Lista Filha';
      try {
        final listaRes = await supabase
            .from('price_lists')
            .select('description')
            .eq('id', targetListId)
            .single();
        nomeListaFilha = listaRes['description']?.toString() ?? 'Lista Filha';
      } catch (_) {}

      final matsFilha = await supabase
          .from('materials')
          .select('id, product_id, description, price')
          .eq('price_list_id', targetListId);

      final productIds = (matsFilha as List)
          .map((m) => m['product_id']?.toString())
          .whereType<String>()
          .toList();
      final clusterMap = await _clusterMapForProducts(productIds);

      final regrasFilha = (excecoesRes as List)
          .where((e) => e['target_list_id']?.toString() == targetListId)
          .toList();

      if (regrasFilha.isEmpty) {
        explicacoes.add(
          '• Lista filha "$nomeListaFilha": herda preços da lista mãe.',
        );
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

      for (final mat in matsFilha) {
        final rowId = mat['id']?.toString() ?? '';
        final pid = mat['product_id']?.toString() ?? '';
        final desc = mat['description']?.toString() ?? 'Sem descrição';
        final precoAtual = _toDouble(mat['price']) ?? 0.0;
        final clusterIdMat = clusterMap[pid];

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
            final sufixo =
                melhorRegra.adjustType == 'percentual' ? '%' : ' R\$';
            origemStr = 'Reajuste $sinal${melhorRegra.valor}$sufixo';
            foiAlterado = precoNovo != precoAtual;
          } else if (precoPropostoMae.containsKey(pid)) {
            precoNovo = precoPropostoMae[pid]!;
            origemStr = 'Herda lista mãe';
            foiAlterado = precoNovo != precoAtual;
          }
        }

        resultado.add(MaterialDraftPreview(
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
        ));
      }
    }

    return DraftPreviewResult(
      materiais: resultado,
      resumo: explicacoes.isEmpty
          ? 'Nenhuma regra ou modificação detectada neste rascunho.'
          : explicacoes.join('\n'),
    );
  }

  /// Publica preços em `materials.price` (por UUID da linha) e marca draft approved.
  Future<int> applyDraft(String draftId) async {
    final draftMeta = await supabase
        .from('price_drafts')
        .select('master_list_id')
        .eq('id', draftId)
        .single();
    final masterListId = draftMeta['master_list_id']?.toString();

    var atualizados = 0;
    final falhas = <String>[];
    final idsJaAtualizados = <String>{};

    // 1) Itens editados manualmente no rascunho (lista em que o usuário trabalhou)
    if (masterListId != null) {
      final itensRes = await supabase
          .from('price_draft_items')
          .select('product_id, new_price')
          .eq('draft_id', draftId);

      final matsMae = await supabase
          .from('materials')
          .select('id, product_id')
          .eq('price_list_id', masterListId);

      final idPorProduto = <String, String>{};
      for (final row in matsMae as List) {
        final pid = row['product_id']?.toString();
        final id = row['id']?.toString();
        if (pid != null && id != null) idPorProduto[pid] = id;
      }

      for (final item in itensRes as List) {
        final pid = item['product_id']?.toString();
        final novo = _toDouble(item['new_price']);
        if (pid == null || novo == null) continue;

        final rowId = _resolverMaterialRowId(idPorProduto, pid);
        if (rowId == null) {
          falhas.add('$pid (lista mãe): linha não encontrada em materials');
          continue;
        }

        try {
          await _persistirPreco(rowId, novo);
          idsJaAtualizados.add(rowId);
          atualizados++;
        } catch (e) {
          falhas.add('$pid (lista mãe): $e');
        }
      }
    }

    // 2) Demais alterações do preview (listas filhas, herança, regras)
    final preview = await buildPreview(draftId);
    for (final m in preview.materiais) {
      if ((m.precoNovo - m.precoAntigo).abs() < 0.001) continue;
      if (m.materialRowId.isEmpty) {
        falhas.add(
          '${m.productId} em "${m.listaNome}": sem id em materials',
        );
        continue;
      }
      if (idsJaAtualizados.contains(m.materialRowId)) continue;

      try {
        await _persistirPreco(m.materialRowId, m.precoNovo);
        idsJaAtualizados.add(m.materialRowId);
        atualizados++;
      } catch (e) {
        falhas.add('${m.productId} em "${m.listaNome}": $e');
      }
    }

    if (atualizados == 0) {
      final detalhe =
          falhas.isNotEmpty ? '\n${falhas.take(8).join('\n')}' : '';
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

  /// Grava preço aprovado em `materials` e confere leitura.
  ///
  /// Também define [is_fixed] = true para evitar que triggers do banco
  /// recalculem o preço (comum quando existe regra SAP / porcentagem).
  Future<void> _persistirPreco(String materialRowId, double novoPreco) async {
    await supabase.from('materials').update({
      'price': novoPreco,
      'is_fixed': true,
    }).eq('id', materialRowId);

    final conferencia = await supabase
        .from('materials')
        .select('price, is_fixed')
        .eq('id', materialRowId)
        .maybeSingle();

    if (conferencia == null) {
      throw Exception(
        'sem permissão de leitura após gravar (verifique RLS SELECT em materials)',
      );
    }

    final gravado = _toDouble(conferencia['price']);
    if (gravado == null || (gravado - novoPreco).abs() > 0.02) {
      throw Exception(
        'preço não persistiu (esperado $novoPreco, banco retornou $gravado). '
        'Provável trigger/função no Supabase recalculando materials.price — '
        'veja Database → Triggers na tabela materials.',
      );
    }
  }

  String? _resolverMaterialRowId(Map<String, String> idPorProduto, String pid) {
    if (idPorProduto.containsKey(pid)) return idPorProduto[pid];
    final t = pid.trim();
    for (final e in idPorProduto.entries) {
      if (e.key.trim() == t) return e.value;
    }
    final pInt = int.tryParse(t);
    if (pInt != null) {
      for (final e in idPorProduto.entries) {
        final kInt = int.tryParse(e.key.trim());
        if (kInt == pInt) return e.value;
      }
    }
    return null;
  }

  Future<Map<String, String>> _clusterMapForProducts(
    List<String> codes,
  ) async {
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
