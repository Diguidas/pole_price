// lib/service/permissao_service.dart

import 'package:pole_price/models/permissao_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PermissaoService {
  final SupabaseClient supabase;

  PermissaoService(this.supabase);

  // ── Leitura ───────────────────────────────────────────────────────────────

  /// Carrega a permissão completa de um usuário pelo email.
  /// Retorna null se o usuário não tiver role cadastrada.
  Future<UsuarioPermissao?> getPermissao(String email) async {
    final roleRes = await supabase
        .from('user_roles')
        .select('role')
        .eq('email', email)
        .maybeSingle();

    if (roleRes == null) return null;

    final role = UserRole.fromString(roleRes['role'] as String);

    // Admin não precisa de permissões granulares
    if (role == UserRole.admin) {
      return UsuarioPermissao(email: email, role: role);
    }

    final listPermsRes = await supabase
        .from('user_list_permissions')
        .select('price_list_id')
        .eq('email', email);

    final groupPermsRes = await supabase
        .from('user_group_permissions')
        .select('pricing_cluster_id')
        .eq('email', email);

    return UsuarioPermissao(
      email: email,
      role: role,
      listIds: (listPermsRes as List)
          .map((r) => r['price_list_id'].toString())
          .toList(),
      clusterIds: (groupPermsRes as List)
          .map((r) => r['pricing_cluster_id'].toString())
          .toList(),
    );
  }

  /// Lista todos os usuários com roles cadastradas.
  Future<List<UsuarioPermissao>> listarTodos() async {
    final rolesRes = await supabase
        .from('user_roles')
        .select('email, role')
        .order('email');

    final emails =
        (rolesRes as List).map((r) => r['email'].toString()).toList();

    if (emails.isEmpty) return [];

    final listPermsRes = await supabase
        .from('user_list_permissions')
        .select('email, price_list_id')
        .inFilter('email', emails);

    final groupPermsRes = await supabase
        .from('user_group_permissions')
        .select('email, pricing_cluster_id')
        .inFilter('email', emails);

    // Monta mapas email → [ids]
    final Map<String, List<String>> listMap = {};
    for (final r in listPermsRes as List) {
      final e = r['email'].toString();
      listMap.putIfAbsent(e, () => []).add(r['price_list_id'].toString());
    }

    final Map<String, List<String>> groupMap = {};
    for (final r in groupPermsRes as List) {
      final e = r['email'].toString();
      groupMap.putIfAbsent(e, () => []).add(r['pricing_cluster_id'].toString());
    }

    return (rolesRes as List).map((r) {
      final email = r['email'].toString();
      return UsuarioPermissao(
        email: email,
        role: UserRole.fromString(r['role'].toString()),
        listIds: listMap[email] ?? [],
        clusterIds: groupMap[email] ?? [],
      );
    }).toList();
  }

  // ── Escrita ───────────────────────────────────────────────────────────────

  /// Cria ou atualiza a role de um usuário.
  Future<void> salvarRole(String email, UserRole role) async {
    await supabase.from('user_roles').upsert(
      {'email': email, 'role': role.value, 'updated_at': DateTime.now().toIso8601String()},
      onConflict: 'email',
    );
  }

  /// Substitui completamente as permissões de listas de um usuário.
  Future<void> salvarListPermissions(
      String email, List<String> listIds) async {
    await supabase
        .from('user_list_permissions')
        .delete()
        .eq('email', email);

    if (listIds.isNotEmpty) {
      await supabase.from('user_list_permissions').insert(
            listIds.map((id) => {'email': email, 'price_list_id': id}).toList(),
          );
    }
  }

  /// Substitui completamente as permissões de grupos de um usuário.
  Future<void> salvarGroupPermissions(
      String email, List<String> clusterIds) async {
    await supabase
        .from('user_group_permissions')
        .delete()
        .eq('email', email);

    if (clusterIds.isNotEmpty) {
      await supabase.from('user_group_permissions').insert(
            clusterIds
                .map((id) => {'email': email, 'pricing_cluster_id': id})
                .toList(),
          );
    }
  }

  /// Salva role + permissões de uma vez.
  Future<void> salvarPermissaoCompleta(UsuarioPermissao permissao) async {
    await salvarRole(permissao.email, permissao.role);
    await Future.wait([
      salvarListPermissions(permissao.email, permissao.listIds),
      salvarGroupPermissions(permissao.email, permissao.clusterIds),
    ]);
  }

  /// Remove um usuário completamente (role + permissões).
  Future<void> removerUsuario(String email) async {
    await Future.wait([
      supabase.from('user_roles').delete().eq('email', email),
      supabase.from('user_list_permissions').delete().eq('email', email),
      supabase.from('user_group_permissions').delete().eq('email', email),
    ]);
  }
}