// sidebar.dart
import 'package:flutter/material.dart';
import 'package:pole_price/screens/grupos_screen.dart';
import 'package:pole_price/screens/home_screen.dart';
import 'package:pole_price/screens/politicas_screen.dart';
import 'package:pole_price/screens/preco_screen.dart';
import 'package:pole_price/screens/definir_aprovacoes_screen.dart';

class Sidebar extends StatefulWidget {
  final String paginaAtiva;

  const Sidebar({super.key, this.paginaAtiva = 'precos'});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> with SingleTickerProviderStateMixin {
  bool _recolhida = false;

  @override
  Widget build(BuildContext context) {
    final double largura = _recolhida ? 64 : 220;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: largura,
      color: Colors.white,
      child: Column(
        children: [
          // Header com botão de toggle e LOGO incorporada
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              mainAxisAlignment: _recolhida
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.spaceBetween,
              children: [
                if (!_recolhida)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      children: [
                        // LOGO DA SIDEBAR (EXPANDIDA)
                        Image.asset(
                          'assets/images/logo_sidebar.png', // Caminho do seu asset
                          height: 32,
                          errorBuilder: (context, error, stackTrace) => const Text(
                            'POLE PRICE',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFFFF6B00),
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    _recolhida ? Icons.menu_open : Icons.menu,
                    color: Colors.grey.shade600,
                  ),
                  onPressed: () => setState(() => _recolhida = !_recolhida),
                  tooltip: _recolhida ? 'Expandir menu' : 'Recolher menu',
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Itens de navegação
          _item(
            context,
            label: 'Home',
            icon: Icons.home_outlined,
            ativo: widget.paginaAtiva == 'home',
            onTap: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            },
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
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AprovacoesScreen()),
              );
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
                  MaterialPageRoute(builder: (_) => const PoliticasScreen()),
                );
              }
            },
          ),

          const Spacer(),

          if (!_recolhida)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Versão 1.0.0',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ),
          if (_recolhida) const SizedBox(height: 16),
        ],
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          padding: EdgeInsets.symmetric(
            horizontal: _recolhida ? 0 : 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: ativo ? cor.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: _recolhida
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: ativo ? cor : Colors.grey.shade600),
              if (!_recolhida) ...[
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: ativo ? cor : Colors.black87,
                    fontWeight: ativo ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}