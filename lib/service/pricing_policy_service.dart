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

  /// Atualiza margem_flat e margem_oferta de uma política
  Future<void> updatePolicy({
    required String id,
    required double? margemFlat,
    required double? margemOferta,
    String? descricao,
  }) async {
    await supabase.from('pricing_policies').update({
      'margem_flat': margemFlat,
      'margem_oferta': margemOferta,
      'descricao': descricao,
    }).eq('id', id);
  }
}