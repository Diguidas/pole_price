// lib/widgets/app_shell.dart
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
        AppPage.home => Icons.home_rounded,
        AppPage.precos => Icons.attach_money_rounded,
        AppPage.grupos => Icons.account_tree_rounded,
        AppPage.aprovacoes => Icons.check_circle_rounded,
        AppPage.historico => Icons.history_rounded,
        AppPage.politicas => Icons.policy_rounded,
        AppPage.relatorio => Icons.bar_chart_rounded,
        AppPage.config => Icons.settings_rounded,
      };

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

class _AppShellScope extends InheritedWidget {
  final _AppShellState state;
  const _AppShellScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_AppShellScope old) => false;
}

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
        backgroundColor: const Color(0xFFF4F6F8),
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

class _AppSidebar extends StatefulWidget {
  final AppPage paginaAtiva;
  final void Function(AppPage) onSelect;
  const _AppSidebar({required this.paginaAtiva, required this.onSelect});

  @override
  State<_AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<_AppSidebar> {
  bool _recolhida = false;
  
  static const _laranjaFundo = Color(0xFFFF6B00);
  static const _brancoPuro = Colors.white;
  static final _brancoOpaco = Colors.white.withOpacity(0.70);
  static final _brancoHover = Colors.white.withOpacity(0.08);

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
    final double largura = _recolhida ? 72 : 240;

    final paginasVisiveis = _mainPages.where((p) => p.podeVer(permCtrl)).toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      width: largura,
      decoration: const BoxDecoration(
        color: _laranjaFundo,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 16,
            offset: Offset(4, 0),
          )
        ],
      ),
      child: OverflowBox(
        maxWidth: largura,
        minWidth: largura,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: largura,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header (Logo) ─────────────────────────────────────────
              SizedBox(
                height: 80,
                width: largura,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _recolhida
                      ? Center(
                          child: IconButton(
                            icon: const Icon(Icons.menu, color: _brancoPuro),
                            onPressed: () => setState(() => _recolhida = false),
                            tooltip: 'Expandir menu',
                          ),
                        )
                      : Row(
                          children: [
                            const SizedBox(width: 8),
                            Expanded(
                              child: Image.asset(
                                'assets/logon.png',
                                height: 50,
                                alignment: Alignment.centerLeft,
                                color: _brancoPuro, 
                                errorBuilder: (_, __, ___) => const Text(
                                  'Pole Price',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800, // Força o bold geométrico da Poppins
                                    fontSize: 16,
                                    color: _brancoPuro,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.menu_open, color: _brancoPuro),
                              onPressed: () => setState(() => _recolhida = true),
                              tooltip: 'Recolher menu',
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 8),

              // ── Itens Principais do Menu ──────────────────────────────
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  children: paginasVisiveis.map((page) => _item(page)).toList(),
                ),
              ),

              // ── Configurações (Fixo embaixo se for Admin) ──────────────
              if (AppPage.config.podeVer(permCtrl)) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Divider(height: 1, color: Colors.white.withOpacity(0.15)),
                ),
                _item(AppPage.config),
                const SizedBox(height: 8),
              ],

              // ── Rodapé com a versão ────────────────────────────────────
              if (!_recolhida)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20, left: 24),
                  child: Text(
                    'Versão 1.0.0',
                    style: TextStyle(
                      fontSize: 11, 
                      fontWeight: FontWeight.w400, // Ajuste sutil para a Poppins pequena
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ),
              if (_recolhida) const SizedBox(height: 20),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Material(
          color: ativo ? _brancoPuro : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          elevation: ativo ? 2 : 0,
          shadowColor: Colors.black.withOpacity(0.1),
          child: InkWell(
            onTap: () => widget.onSelect(page),
            borderRadius: BorderRadius.circular(24),
            hoverColor: _brancoHover,
            splashColor: _brancoHover,
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _recolhida ? 0 : 16),
                child: _recolhida
                    ? Center(
                        child: Icon(
                          page.icon,
                          size: 24,
                          color: ativo ? _laranjaFundo : _brancoOpaco, 
                        ),
                      )
                    : Row(
                        children: [
                          Icon(
                            page.icon,
                            size: 22,
                            color: ativo ? _laranjaFundo : _brancoOpaco,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              page.label,
                              style: TextStyle(
                                fontSize: 14,
                                letterSpacing: 0.2,
                                // Poppins SemiBold no item ativo e Medium no inativo para máxima legibilidade
                                fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                                color: ativo ? _laranjaFundo : _brancoOpaco,
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