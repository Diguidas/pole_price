import 'package:pole_price/models/pricing_policy_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PricingPolicyService {
  final SupabaseClient supabase;

  PricingPolicyService(this.supabase);

  /// Busca todas as políticas com as listas vinculadas
  Future<List<PricingPolicy>> getPolicies() async {
    final res = await supabase
        .from('pricing_policies')
        .select('*, price_lists(id, description, regra_exclusiva)')
        .order('name');

    return (res as List).map((e) => PricingPolicy.fromJson(e)).toList();
  }

  /// Busca todas as price_lists (independente de vínculo)
  Future<List<AllPriceList>> getAllPriceLists() async {
    final res = await supabase
        .from('price_lists')
        .select('id, description, policy_id')
        .order('description');

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
    await supabase.from('pricing_policies').update({
      'name': name,
      'margem_flat': margemFlat,
      'margem_oferta': margemOferta,
      'descricao': descricao,
    }).eq('id', id);
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