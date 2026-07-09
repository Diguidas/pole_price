import 'package:pole_price/models/pricing_policy_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PricingPolicyService {
  final SupabaseClient supabase;

  PricingPolicyService(this.supabase);

  // ── Listar políticas com listas vinculadas ────────────────────────────────

  Future<List<PricingPolicy>> getPolicies() async {
    final policiesRes = await supabase
        .from('pricing_policies')
        .select('*')
        .order('name');

    // Busca todas as listas com seus campos de exceção e espelho
    final listsRes = await supabase
        .from('price_lists')
        .select('pltyp, ptext, policy_id, excecao_flat_pct, excecao_oferta_pct, mirror_of_pltyp')
        .not('policy_id', 'is', null);

    final allLists = listsRes as List;

    // Monta mapa de filhas por mãe para preencher mirrorFilhas
    final Map<String, List<String>> filhasPorMae = {};
    for (final l in allLists) {
      final mae = l['mirror_of_pltyp']?.toString();
      if (mae != null) {
        filhasPorMae.putIfAbsent(mae, () => []).add(l['pltyp'].toString());
      }
    }

    // Agrupa por política
    final Map<String, List<Map<String, dynamic>>> listsByPolicy = {};
    for (final l in allLists) {
      final pid = l['policy_id'] as String?;
      if (pid != null) {
        final enriched = Map<String, dynamic>.from(l);
        enriched['mirror_filhas'] = filhasPorMae[l['pltyp']?.toString()] ?? [];
        listsByPolicy.putIfAbsent(pid, () => []).add(enriched);
      }
    }

    return (policiesRes as List).map((policy) {
      final enriched = Map<String, dynamic>.from(policy);
      enriched['price_lists'] = listsByPolicy[policy['id']] ?? [];
      return PricingPolicy.fromJson(enriched);
    }).toList();
  }

  // ── Política de uma lista específica (com listas irmãs) ───────────────────

  Future<PricingPolicy?> getPolicyForLista(String pltyp) async {
    final policies = await getPolicies();
    for (final p in policies) {
      if (p.listas.any((l) => l.pltyp == pltyp)) return p;
    }
    return null;
  }

  // ── Todas as listas (para modal de vinculação) ────────────────────────────

  Future<List<AllPriceList>> getAllPriceLists() async {
    final res = await supabase
        .from('price_lists')
        .select('pltyp, ptext, policy_id, excecao_flat_pct, excecao_oferta_pct, mirror_of_pltyp')
        .order('ptext');

    return (res as List).map((e) => AllPriceList.fromJson(e)).toList();
  }

  // ── CRUD de políticas ─────────────────────────────────────────────────────

  Future<void> createPolicy({
    required String id,
    required String name,
    double? margemFlat,
    double? margemOferta,
    String? descricao,
  }) async {
    await supabase.from('pricing_policies').insert({
      'id': id,
      'name': name,
      'margem_flat': margemFlat,
      'margem_oferta': margemOferta,
      'descricao': descricao,
    });
  }

  Future<void> updatePolicy({
    required String id,
    required String name,
    required double? margemFlat,
    required double? margemOferta,
    String? descricao,
  }) async {
    await supabase
        .from('pricing_policies')
        .update({
          'name': name,
          'margem_flat': margemFlat,
          'margem_oferta': margemOferta,
          'descricao': descricao,
        })
        .eq('id', id);
  }

  Future<void> deletePolicy(String id) async {
    // Desvincula listas (limpa policy_id, exceções e espelhos)
    await supabase
        .from('price_lists')
        .update({
          'policy_id': null,
          'excecao_flat_pct': null,
          'excecao_oferta_pct': null,
          'mirror_of_pltyp': null,
        })
        .eq('policy_id', id);
    await supabase.from('pricing_policies').delete().eq('id', id);
  }

  // ── Vincular / desvincular lista ──────────────────────────────────────────

  Future<void> vincularLista({
    required String listaId,
    required String policyId,
  }) async {
    await supabase
        .from('price_lists')
        .update({'policy_id': policyId})
        .eq('pltyp', listaId);
  }

  Future<void> desvincularLista(String listaId) async {
    await supabase
        .from('price_lists')
        .update({
          'policy_id': null,
          'excecao_flat_pct': null,
          'excecao_oferta_pct': null,
          'mirror_of_pltyp': null,
        })
        .eq('pltyp', listaId);

    // Remove espelhos que apontavam para esta lista
    await supabase
        .from('price_lists')
        .update({'mirror_of_pltyp': null})
        .eq('mirror_of_pltyp', listaId);
  }

  // ── Salvar exceção de margem ──────────────────────────────────────────────
  // Salva na lista mãe E propaga para todas as filhas espelho

  Future<void> salvarExcecao({
    required String listaId,
    double? excecaoFlatPct,
    double? excecaoOfertaPct,
  }) async {
    // Atualiza a lista mãe
    await supabase
        .from('price_lists')
        .update({
          'excecao_flat_pct': excecaoFlatPct,
          'excecao_oferta_pct': excecaoOfertaPct,
        })
        .eq('pltyp', listaId);

    // Propaga para filhas espelho
    await supabase
        .from('price_lists')
        .update({
          'excecao_flat_pct': excecaoFlatPct,
          'excecao_oferta_pct': excecaoOfertaPct,
        })
        .eq('mirror_of_pltyp', listaId);
  }

  // ── Definir espelho ───────────────────────────────────────────────────────
  // listaFilhaId passa a espelhar listaMaeId (herda exceção imediatamente)

  Future<void> definirEspelho({
    required String listaMaeId,
    required String listaFilhaId,
    required String policyId,
  }) async {
    // Busca exceção atual da mãe
    final res = await supabase
        .from('price_lists')
        .select('excecao_flat_pct, excecao_oferta_pct')
        .eq('pltyp', listaMaeId)
        .single();

    await supabase
        .from('price_lists')
        .update({
          'mirror_of_pltyp': listaMaeId,
          'policy_id': policyId,
          'excecao_flat_pct': res['excecao_flat_pct'],
          'excecao_oferta_pct': res['excecao_oferta_pct'],
        })
        .eq('pltyp', listaFilhaId);
  }

  Future<void> removerEspelho(String listaFilhaId) async {
    await supabase
        .from('price_lists')
        .update({
          'mirror_of_pltyp': null,
          'excecao_flat_pct': null,
          'excecao_oferta_pct': null,
        })
        .eq('pltyp', listaFilhaId);
  }
}