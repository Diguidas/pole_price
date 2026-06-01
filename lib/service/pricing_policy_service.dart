import 'package:pole_price/models/pricing_policy_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PricingPolicyService {
  final SupabaseClient supabase;

  PricingPolicyService(this.supabase);

  Future<List<PricingPolicy>> getPolicies() async {
    final policiesRes = await supabase
        .from('pricing_policies')
        .select('*')
        .order('name');

    final listsRes = await supabase
        .from('price_lists')
        .select('pltyp, ptext, policy_id')
        .not('policy_id', 'is', null);

    final Map<String, List<Map<String, dynamic>>> listsByPolicy = {};
    for (final list in listsRes as List) {
      final pid = list['policy_id'] as String?;
      if (pid != null) listsByPolicy.putIfAbsent(pid, () => []).add(list);
    }

    return (policiesRes as List).map((policy) {
      final enriched = Map<String, dynamic>.from(policy);
      enriched['price_lists'] = listsByPolicy[policy['id']] ?? [];
      return PricingPolicy.fromJson(enriched);
    }).toList();
  }

  Future<List<AllPriceList>> getAllPriceLists() async {
    final res = await supabase
        .from('price_lists')
        .select('pltyp, ptext, policy_id')
        .order('ptext');

    return (res as List).map((e) => AllPriceList.fromJson(e)).toList();
  }

  /// Cria uma nova política
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

  /// Atualiza uma política existente
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

  /// Exclui uma política (desvincula as listas antes)
  Future<void> deletePolicy(String id) async {
    await supabase
        .from('price_lists')
        .update({'policy_id': null})
        .eq('policy_id', id);
    await supabase.from('pricing_policies').delete().eq('id', id);
  }

  /// Vincula uma lista a esta política (sobrescreve vínculo anterior)
  Future<void> vincularLista({
    required String listaId,
    required String policyId,
  }) async {
    await supabase
        .from('price_lists')
        .update({'policy_id': policyId})
        .eq('id', listaId);
  }

  /// Remove o vínculo de uma lista com qualquer política
  Future<void> desvincularLista(String listaId) async {
    await supabase
        .from('price_lists')
        .update({'policy_id': null})
        .eq('id', listaId);
  }
}
