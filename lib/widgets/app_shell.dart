// lib/widgets/app_shell.dart  (versão atualizada com permissões)
//
// Diferença da versão anterior:
// - Sidebar filtra itens com base no PermissaoController
// - AppPage.config adicionado para a tela de configurações (só admin)

import 'package:flutter/material.dart';
import 'package:pole_price/controllers/permissao_controller.dart';
import 'package:pole_price/screens/home_screen.dart';
import 'package:pole_price/screens/preco_screen.dart';
import 'package:pole_price/screens/grupos_screen.dart';
import 'package:pole_price/screens/definir_aprovacoes_screen.dart';
import 'package:pole_price/screens/historico_screen.dart';
import 'package:pole_price/screens/politicas_screen.dart';
import 'package:pole_price/screens/relatorio_screen.dart';
import 'package:pole_price/screens/config_screen.dart';

enum AppPage {
  home,
  precos,
  grupos,
  aprovacoes,
  historico,
  politicas,
  relatorio,
  config;

  String get label => switch (this) {
        AppPage.home => 'Home',
        AppPage.precos => 'Preços',
        AppPage.grupos => 'Grupos',
        AppPage.aprovacoes => 'Aprovações',
        AppPage.historico => 'Histórico',
        AppPage.politicas => 'Políticas',
        AppPage.relatorio => 'Relatório',
        AppPage.config => 'Configurações',
      };

  IconData get icon => switch (this) {
        AppPage.home => Icons.home_outlined,
        AppPage.precos => Icons.attach_money,
        AppPage.grupos => Icons.account_tree_outlined,
        AppPage.aprovacoes => Icons.check_circle_outline,
        AppPage.historico => Icons.history_rounded,
        AppPage.politicas => Icons.policy_outlined,
        AppPage.relatorio => Icons.bar_chart_rounded,
        AppPage.config => Icons.settings_outlined,
      };

  /// Verifica se o usuário logado pode ver esta página.
  bool podeVer(PermissaoController p) => switch (this) {
        AppPage.home => true,
        AppPage.precos => p.podeVerPrecos,
        AppPage.grupos => p.podeVerGrupos,
        AppPage.aprovacoes => p.podeVerAprovacoes,
        AppPage.historico => p.podeVerHistorico,
        AppPage.politicas => p.podeVerPoliticas,
        AppPage.relatorio => p.podeVerRelatorio,
        AppPage.config => p.podeVerConfig,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// InheritedWidget para acesso ao shell de qualquer descendente
// ─────────────────────────────────────────────────────────────────────────────
class _AppShellScope extends InheritedWidget {
  final _AppShellState state;
  const _AppShellScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_AppShellScope old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// AppShell
// ─────────────────────────────────────────────────────────────────────────────
class AppShell extends StatefulWidget {
  final AppPage initialPage;
  const AppShell({super.key, this.initialPage = AppPage.home});

  static _AppShellState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_AppShellScope>();
    assert(scope != null, 'AppShell.of() chamado fora de um AppShell');
    return scope!.state;
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppPage _paginaAtiva;

  @override
  void initState() {
    super.initState();
    _paginaAtiva = widget.initialPage;
  }

  void goTo(AppPage page) {
    if (_paginaAtiva == page) return;
    setState(() => _paginaAtiva = page);
  }

  @override
  Widget build(BuildContext context) {
    return _AppShellScope(
      state: this,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: Row(
          children: [
            _AppSidebar(paginaAtiva: _paginaAtiva, onSelect: goTo),
            Expanded(
              child: IndexedStack(
                index: _paginaAtiva.index,
                children: const [
                  HomeScreen(),
                  PrecoScreen(),
                  GruposScreen(),
                  AprovacoesScreen(),
                  HistoricoScreen(),
                  PoliticasScreen(),
                  RelatorioScreen(),
                  ConfigScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar com filtro de permissões
// ─────────────────────────────────────────────────────────────────────────────
class _AppSidebar extends StatefulWidget {
  final AppPage paginaAtiva;
  final void Function(AppPage) onSelect;
  const _AppSidebar({required this.paginaAtiva, required this.onSelect});

  @override
  State<_AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<_AppSidebar> {
  bool _recolhida = false;
  static const _laranja = Color(0xFFFF6B00);

  // Páginas da seção principal (aparecem em ordem, filtradas por permissão)
  static const _mainPages = [
    AppPage.home,
    AppPage.precos,
    AppPage.grupos,
    AppPage.aprovacoes,
    AppPage.historico,
    AppPage.politicas,
    AppPage.relatorio,
  ];

  @override
  Widget build(BuildContext context) {
    final permCtrl = PermissaoController.instance;
    final double largura = _recolhida ? 64 : 220;

    final paginasVisiveis =
        _mainPages.where((p) => p.podeVer(permCtrl)).toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: largura,
      color: Colors.white,
      child: OverflowBox(
        maxWidth: largura,
        minWidth: largura,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: largura,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────
              SizedBox(
                height: 64,
                width: largura,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: Colors.grey.shade100)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _recolhida
                        ? Center(
                            child: IconButton(
                              icon: Icon(Icons.menu,
                                  color: Colors.grey.shade600),
                              onPressed: () =>
                                  setState(() => _recolhida = false),
                              tooltip: 'Expandir menu',
                            ),
                          )
                        : Row(
                            children: [
                              const SizedBox(width: 8),
                              Expanded(
                                child: Image.asset(
                                  'assets/logo.png',
                                  height: 32,
                                  alignment: Alignment.centerLeft,
                                  errorBuilder: (_, __, ___) => const Text(
                                    'POLE PRICE',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: _laranja,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.menu,
                                    color: Colors.grey.shade600),
                                onPressed: () =>
                                    setState(() => _recolhida = true),
                                tooltip: 'Recolher menu',
                              ),
                            ],
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Itens principais ───────────────────────────────────────
              ...paginasVisiveis.map((page) => _item(page)),

              const Spacer(),

              // ── Config (admin) — fica no rodapé separado ──────────────
              if (AppPage.config.podeVer(permCtrl)) ...[
                Divider(height: 1, color: Colors.grey.shade100),
                const SizedBox(height: 4),
                _item(AppPage.config),
                const SizedBox(height: 4),
              ],

              if (!_recolhida)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16, left: 16),
                  child: Text(
                    'Versão 1.0.0',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ),
              if (_recolhida) const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(AppPage page) {
    final ativo = widget.paginaAtiva == page;
    return Tooltip(
      message: _recolhida ? page.label : '',
      preferBelow: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Material(
          color: ativo ? _laranja.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => widget.onSelect(page),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 42,
              child: Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: _recolhida ? 0 : 12),
                child: _recolhida
                    ? Center(
                        child: Icon(page.icon,
                            size: 22,
                            color:
                                ativo ? _laranja : Colors.grey.shade600),
                      )
                    : Row(
                        children: [
                          Icon(page.icon,
                              size: 20,
                              color:
                                  ativo ? _laranja : Colors.grey.shade600),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              page.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: ativo
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: ativo
                                    ? _laranja
                                    : Colors.grey.shade700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}