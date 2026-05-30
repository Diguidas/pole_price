// sidebar.dart
import 'package:flutter/material.dart';
import 'package:pole_price/screens/grupos_screen.dart';
import 'package:pole_price/screens/home_screen.dart';
import 'package:pole_price/screens/politicas_screen.dart';
import 'package:pole_price/screens/preco_screen.dart';
import 'package:pole_price/screens/definir_aprovacoes_screen.dart';
import 'package:pole_price/screens/historico_screen.dart';
import 'package:pole_price/screens/relatorio_screen.dart';

class Sidebar extends StatefulWidget {
  final String paginaAtiva;

  const Sidebar({super.key, this.paginaAtiva = 'precos'});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  bool _recolhida = false;

  @override
  Widget build(BuildContext context) {
    final double largura = _recolhida ? 64 : 220;

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
              // ── Header ──────────────────────────────────────────────
              SizedBox(
                height: 64,
                width: largura,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade100),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _recolhida
                        ? Center(
                            child: IconButton(
                              icon: Icon(
                                Icons.menu,
                                color: Colors.grey.shade600,
                              ),
                              onPressed: () =>
                                  setState(() => _recolhida = false),
                              tooltip: 'Expandir menu',
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.max,
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
                                      color: Color(0xFFFF6B00),
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.menu,
                                  color: Colors.grey.shade600,
                                ),
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

              _item(
                context,
                label: 'Home',
                icon: Icons.home_outlined,
                ativo: widget.paginaAtiva == 'home',
                onTap: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                ),
              ),
              _item(
                context,
                label: 'Preços',
                icon: Icons.attach_money,
                ativo: widget.paginaAtiva == 'precos',
                onTap: () {
                  if (widget.paginaAtiva != 'precos') {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const PrecoScreen()),
                    );
                  }
                },
              ),
              _item(
                context,
                label: 'Grupos',
                icon: Icons.account_tree_outlined,
                ativo: widget.paginaAtiva == 'grupos',
                onTap: () {
                  if (widget.paginaAtiva != 'grupos') {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const GruposScreen()),
                    );
                  }
                },
              ),
              _item(
                context,
                label: 'Aprovações',
                icon: Icons.check_circle_outline,
                ativo: widget.paginaAtiva == 'aprovacoes',
                onTap: () {
                  if (widget.paginaAtiva != 'aprovacoes') {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AprovacoesScreen(),
                      ),
                    );
                  }
                },
              ),
              _item(
                context,
                label: 'Histórico',
                icon: Icons.history_rounded,
                ativo: widget.paginaAtiva == 'historico',
                onTap: () {
                  if (widget.paginaAtiva != 'historico') {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HistoricoScreen(),
                      ),
                    );
                  }
                },
              ),
              _item(
                context,
                label: 'Políticas',
                icon: Icons.policy_outlined,
                ativo: widget.paginaAtiva == 'politicas',
                onTap: () {
                  if (widget.paginaAtiva != 'politicas') {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PoliticasScreen(),
                      ),
                    );
                  }
                },
              ),
              _item(
                context,
                label: 'Relatório',
                icon: Icons.bar_chart_rounded,
                ativo: widget.paginaAtiva == 'relatorio',
                onTap: () {
                  if (widget.paginaAtiva != 'relatorio') {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RelatorioScreen(),
                      ),
                    );
                  }
                },
              ),

              const Spacer(),

              if (!_recolhida)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16, left: 16),
                  child: Text(
                    'Versão 1.0.0',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ),
              if (_recolhida) const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool ativo = false,
  }) {
    final cor = const Color(0xFFFF6B00);

    return Tooltip(
      message: _recolhida ? label : '',
      preferBelow: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Material(
          color: ativo ? cor.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 42,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _recolhida ? 0 : 12),
                child: _recolhida
                    ? Center(
                        child: Icon(
                          icon,
                          size: 22,
                          color: ativo ? cor : Colors.grey.shade600,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Icon(
                            icon,
                            size: 22,
                            color: ativo ? cor : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: ativo ? cor : Colors.black87,
                                fontWeight: ativo
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontSize: 14,
                              ),
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
