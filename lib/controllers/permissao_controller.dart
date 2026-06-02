// lib/controllers/permissao_controller.dart
//
// Singleton que carrega as permissões do usuário logado na inicialização.
// Expõe helpers usados pelo AppShell (sidebar), AppGuard (bloqueio de rotas)
// e pelas telas (filtro de listas/grupos).

import 'package:flutter/foundation.dart';
import 'package:pole_price/models/permissao_model.dart';
import 'package:pole_price/service/permissao_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PermissaoController extends ChangeNotifier {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static PermissaoController? _instance;

  static PermissaoController get instance {
    _instance ??= PermissaoController._internal(
      PermissaoService(Supabase.instance.client),
    );
    return _instance!;
  }

  static void reset() {
    _instance?.dispose();
    _instance = null;
  }

  PermissaoController._internal(this._service);

  final PermissaoService _service;

  // ── Estado ────────────────────────────────────────────────────────────────
  UsuarioPermissao? _permissao;
  bool _loading = false;
  String? _erro;

  UsuarioPermissao? get permissao => _permissao;
  bool get loading => _loading;
  String? get erro => _erro;

  /// Retorna true se as permissões já foram carregadas.
  bool get inicializado => _permissao != null;

  // ── Helpers de acesso rápido ──────────────────────────────────────────────
  bool get isAdmin => _permissao?.isAdmin ?? false;
  bool get isGestor => _permissao?.isGestor ?? false;
  bool get isAprovador => _permissao?.isAprovador ?? false;

  /// Pode clicar em Aprovar/Rejeitar na tela de aprovações.
  bool get podeAprovar => isAdmin || isAprovador;

  bool get podeVerPrecos => _permissao?.podeVerPrecos ?? false;
  bool get podeVerAprovacoes => _permissao?.podeVerAprovacoes ?? false;
  bool get podeVerGrupos => _permissao?.podeVerGrupos ?? false;
  bool get podeVerPoliticas => _permissao?.podeVerPoliticas ?? false;
  bool get podeVerHistorico => _permissao?.podeVerHistorico ?? false;
  bool get podeVerRelatorio => _permissao?.podeVerRelatorio ?? false;
  bool get podeVerConfig => _permissao?.podeVerConfig ?? false;

  bool podeEditarLista(String listId) =>
      _permissao?.podeEditarLista(listId) ?? false;

  bool podeEditarCluster(String clusterId) =>
      _permissao?.podeEditarCluster(clusterId) ?? false;

  /// Listas que o usuário pode ver/editar. Lista vazia = todas (admin).
  List<String> get listasPermitidas => _permissao?.listIds ?? [];
  List<String> get clustersPermitidos => _permissao?.clusterIds ?? [];

  // ── Carregamento ──────────────────────────────────────────────────────────

  /// Chame após o login, antes de mostrar o AppShell.
  Future<void> init() async {
    if (_permissao != null) return;

    _loading = true;
    _erro = null;
    notifyListeners();

    try {
      final email = Supabase.instance.client.auth.currentUser?.email;
      print('=== EMAIL DO USUÁRIO LOGADO: $email ===');
      if (email == null) {
        _erro = 'Usuário não autenticado.';
        print('=== ERRO: usuário não autenticado ===');
        return;
      }

      _permissao = await _service.getPermissao(email);

      // Usuário autenticado mas sem role cadastrada — trata como sem acesso.
      if (_permissao == null) {
        _erro = 'sem_permissao';
      }
    } catch (e) {
      _erro = 'Erro ao carregar permissões: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> recarregar() async {
    _permissao = null;
    await init();
  }

  // ── Usado pela ConfigScreen ───────────────────────────────────────────────

  /// Salva as permissões de outro usuário (só admin chega aqui).
  Future<void> salvarPermissao(UsuarioPermissao p) async {
    await _service.salvarPermissaoCompleta(p);
  }

  Future<void> removerUsuario(String email) async {
    await _service.removerUsuario(email);
  }

  Future<List<UsuarioPermissao>> listarTodos() => _service.listarTodos();
  bool get isVisualizador => _permissao?.role == UserRole.visualizador;
}