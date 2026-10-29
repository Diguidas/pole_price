// lib/router.dart
//
// Rotas do app (go_router, estratégia de URL com hash: /#/materiais).
//   /login        → login Microsoft
//   /             → Home
//   /precos       → Gestão de preços (?draft=<id> ou parâmetros da consulta)
//   /materiais, /rascunhos, /aprovacoes[?draft=<id>], /historico,
//   /politicas, /relatorio, /base-preco, /config
//
// Todas, exceto /login, ficam dentro do AppShell (menu lateral) e só abrem
// com sessão ativa; sem sessão, o usuário vai para /login e volta depois.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pole_price/screens/config_screen.dart';
import 'package:pole_price/screens/definir_aprovacoes_screen.dart';
import 'package:pole_price/screens/historico_screen.dart';
import 'package:pole_price/screens/home_screen.dart';
import 'package:pole_price/screens/login_page.dart';
import 'package:pole_price/screens/material/materials_screen.dart';
import 'package:pole_price/screens/politicas_screen.dart';
import 'package:pole_price/screens/precos_rota.dart';
import 'package:pole_price/screens/rascunhos_screen.dart';
import 'package:pole_price/screens/relatorio_base_preco_screen.dart';
import 'package:pole_price/screens/relatorio_screen.dart';
import 'package:pole_price/widgets/app_shell.dart';
import 'package:pole_price/widgets/auth_guard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reavalia os redirects do router quando a sessão muda (login/logout).
class _AuthRefresh extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;

  _AuthRefresh() {
    _sub = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

Page<void> _pagina(GoRouterState state, Widget child) =>
    NoTransitionPage<void>(key: state.pageKey, child: child);

GoRouter criarRouter() {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthRefresh(),
    redirect: (context, state) {
      final logado = Supabase.instance.client.auth.currentSession != null;
      final noLogin = state.matchedLocation == '/login';

      if (!logado) {
        if (noLogin) return null;
        final destino = state.uri.toString();
        return destino == '/'
            ? '/login'
            : '/login?from=${Uri.encodeQueryComponent(destino)}';
      }
      if (noLogin) {
        final from = state.uri.queryParameters['from'];
        return (from != null && from.startsWith('/') && !from.startsWith('/login'))
            ? from
            : '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (c, s) => _pagina(s, const LoginPage()),
      ),
      ShellRoute(
        builder: (context, state, child) => AuthGuard(
          builder: (_) => AppShell(location: state.uri.path, child: child),
        ),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (c, s) => _pagina(s, const HomeScreen()),
          ),
          GoRoute(
            path: '/precos',
            pageBuilder: (c, s) => _pagina(
              s,
              PrecosRota(
                key: ValueKey(s.uri.toString()),
                draftId: s.uri.queryParameters['draft'],
                params: PrecoParams.fromQuery(s.uri.queryParameters),
              ),
            ),
          ),
          GoRoute(
            path: '/materiais',
            pageBuilder: (c, s) => _pagina(s, const MaterialsScreen()),
          ),
          GoRoute(
            path: '/rascunhos',
            pageBuilder: (c, s) => _pagina(s, const RascunhosScreen()),
          ),
          GoRoute(
            path: '/aprovacoes',
            pageBuilder: (c, s) => _pagina(
              s,
              AprovacoesScreen(
                key: ValueKey(s.uri.queryParameters['draft']),
                draftIdInicial: s.uri.queryParameters['draft'],
              ),
            ),
          ),
          GoRoute(
            path: '/historico',
            pageBuilder: (c, s) => _pagina(s, const HistoricoScreen()),
          ),
          GoRoute(
            path: '/politicas',
            pageBuilder: (c, s) => _pagina(s, const PoliticasScreen()),
          ),
          GoRoute(
            path: '/relatorio',
            pageBuilder: (c, s) => _pagina(s, const RelatorioScreen()),
          ),
          GoRoute(
            path: '/base-preco',
            pageBuilder: (c, s) => _pagina(s, const RelatorioBasePrecoScreen()),
          ),
          GoRoute(
            path: '/config',
            pageBuilder: (c, s) => _pagina(s, const ConfigScreen()),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Página não encontrada'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go('/'),
              child: const Text('Ir para o início'),
            ),
          ],
        ),
      ),
    ),
  );
}
