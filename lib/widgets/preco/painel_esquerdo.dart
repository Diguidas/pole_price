import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/material_preco.dart';
import 'package:pole_price/widgets/tabela_precos.dart';
import 'package:pole_price/widgets/preco/busca_material_sheet.dart';
import 'package:pole_price/widgets/preco/preco_topbar.dart'; // _VigenciaGlobalButton

const _laranja = Color(0xFFFF6B00);

class PainelEsquerdo extends StatefulWidget {
  final PrecoController controller;
  const PainelEsquerdo({super.key, required this.controller});

  @override
  State<PainelEsquerdo> createState() => _PainelEsquerdoState();
}

class _PainelEsquerdoState extends State<PainelEsquerdo> {
  // ScrollController local — garantidamente attachado ao ListView desta tela.
  // Vive aqui (StatefulWidget) e não no controller singleton, o que evita
  // o problema de hasClients == false após rebuilds.
  final _scrollCtrl = ScrollController();

  PrecoController get c => widget.controller;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final temDados = c.materiais.isNotEmpty;

    return SizedBox(
      height: double.infinity,
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _numeroBadge('1'),
                    const SizedBox(width: 10),
                    const Text(
                      'Materiais',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (c.pltyp != null)
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Adicionar material'),
                        style: TextButton.styleFrom(foregroundColor: _laranja),
                        onPressed: () => _abrirBuscaMaterial(context),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Busca ─────────────────────────────────────────
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Buscar material...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onChanged: c.buscar,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ── Vigência global (vinda do topbar) ─────────────
                    VigenciaGlobalButton(controller: c),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: TabelaPrecos(controller: c),
          ),

          if (c.pltyp != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Text(
                'Exibindo ${c.filtrados.length} de ${c.materiais.where((m) => !m.removido).length} materiais',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    )); // SizedBox + Container
  }

  Future<void> _abrirBuscaMaterial(BuildContext context) async {
    final materiais = await showDialog<List<MaterialPreco>>(
      context: context,
      builder: (_) => BuscaMaterialSheet(controller: c),
    );
    if (materiais != null && materiais.isNotEmpty) {
      final jaExistiam = <String>[];
      for (final m in materiais) {
        if (!c.adicionarMaterial(m)) jaExistiam.add(m.codigo);
      }
      if (jaExistiam.isNotEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              jaExistiam.length == 1
                  ? 'Material ${jaExistiam.first} já está na lista.'
                  : '${jaExistiam.length} materiais já estavam na lista: ${jaExistiam.join(', ')}',
            ),
          ),
        );
      }
    }
  }

  Widget _numeroBadge(String n) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: _laranja,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          n,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}