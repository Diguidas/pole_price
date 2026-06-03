// lib/models/permissao_model.dart

enum UserRole {
  admin,
  gestor,
  aprovador,
  visualizador;

  static UserRole fromString(String s) => switch (s) {
        'admin' => UserRole.admin,
        'gestor' => UserRole.gestor,
        'aprovador' => UserRole.aprovador,
        'visualizador' => UserRole.visualizador,
        _ => UserRole.aprovador,
      };

  String get label => switch (this) {
        UserRole.admin => 'Admin',
        UserRole.gestor => 'Gestor de Preços',
        UserRole.aprovador => 'Aprovador',
        UserRole.visualizador => 'Visualizador',
      };

  String get value => name; // 'admin' | 'gestor' | 'aprovador'
}

class UsuarioPermissao {
  final String email;
  final UserRole role;
  final List<String> listIds;    // price_list_ids permitidas
  final List<String> clusterIds; // pricing_cluster_ids permitidos

  const UsuarioPermissao({
    required this.email,
    required this.role,
    this.listIds = const [],
    this.clusterIds = const [],
  });

  bool get isAdmin => role == UserRole.admin;
  bool get isGestor => role == UserRole.gestor;
  bool get isAprovador => role == UserRole.aprovador;

  /// Admin sempre pode tudo. Gestor verifica a lista de permissões.
  bool podeEditarLista(String listId) {
    if (isAdmin) return true;
    if (!isGestor) return false;
    return listIds.isEmpty || listIds.contains(listId);
  }

  bool podeEditarCluster(String clusterId) {
    if (isAdmin) return true;
    if (!isGestor) return false;
    return clusterIds.isEmpty || clusterIds.contains(clusterId);
  }

  // Acesso a telas
  bool get podeVerPrecos => isAdmin || isGestor;
  bool get podeVerRascunhos => isAdmin || isGestor;
  bool get podeVerAprovacoes => isAdmin || isAprovador;
  bool get podeVerGrupos => isAdmin || isGestor;
  bool get podeVerPoliticas => isAdmin;
  bool get podeVerHistorico => isAdmin || isAprovador || isGestor;
  bool get podeVerRelatorio => isAdmin || isAprovador || isGestor;
  bool get podeVerConfig => isAdmin;

  UsuarioPermissao copyWith({
    String? email,
    UserRole? role,
    List<String>? listIds,
    List<String>? clusterIds,
  }) =>
      UsuarioPermissao(
        email: email ?? this.email,
        role: role ?? this.role,
        listIds: listIds ?? this.listIds,
        clusterIds: clusterIds ?? this.clusterIds,
      );
}