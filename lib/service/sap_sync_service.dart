import 'package:supabase_flutter/supabase_flutter.dart';

class SapSyncResult {
  final int materiaisAtualizados;
  final String? mensagem;

  SapSyncResult({required this.materiaisAtualizados, this.mensagem});
}

/// Sincronização SAP ↔ Supabase via Edge Functions (somente sob demanda).
///
/// A tela de preços lê sempre do Supabase. SAP só entra aqui:
///   - `sync-sap-prices`  → SAP → Supabase (botão "Buscar do SAP")
///   - `push-sap-prices`  → Supabase → SAP (após aprovação; não altera a leitura da tela)
class SapSyncService {
  final SupabaseClient supabase;

  SapSyncService(this.supabase);

  /// Puxa preços do SAP para o Supabase.
  /// [listId] opcional — se informado, sincroniza apenas essa lista.
  Future<SapSyncResult> syncFromSap({String? listId}) async {
    final res = await supabase.functions.invoke(
      'sync-sap-prices',
      body: {if (listId != null) 'list_id': listId},
    );

    if (res.status != 200) {
      throw Exception(
        'Falha ao sincronizar SAP (${res.status}): ${res.data}',
      );
    }

    final data = res.data;
    if (data is Map) {
      return SapSyncResult(
        materiaisAtualizados: (data['updated'] as num?)?.toInt() ?? 0,
        mensagem: data['message']?.toString(),
      );
    }
    return SapSyncResult(materiaisAtualizados: 0);
  }

  /// Envia preços aprovados do Supabase para o SAP.
  Future<void> pushToSap({required String draftId}) async {
    final res = await supabase.functions.invoke(
      'push-sap-prices',
      body: {'draft_id': draftId},
    );

    if (res.status != 200) {
      throw Exception(
        'Falha ao enviar preços ao SAP (${res.status}): ${res.data}',
      );
    }
  }
}
