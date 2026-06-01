import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/material_preco.dart';
import 'package:pole_price/widgets/tabela_precos.dart';
import 'package:pole_price/widgets/preco/seletor_lista_mae.dart';
import 'package:pole_price/widgets/preco/busca_material_sheet.dart';

const _laranja = Color(0xFFFF6B00);

class PainelEsquerdo extends StatelessWidget {
  final PrecoController controller;
  const PainelEsquerdo({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final temDados = controller.materiais.isNotEmpty;

    return Container(
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    // ── Botão adicionar material ──────────────────────
                    if (temDados)
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Adicionar material'),
                        style: TextButton.styleFrom(foregroundColor: _laranja),
                        onPressed: () => _abrirBuscaMaterial(context),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: controller.buscar,
                ),
              ],
            ),
          ),

          if (temDados)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  _colHeader('Código', flex: 2),
                  _colHeader('Descrição do Material', flex: 5),
                  _colHeader('Preço Atual (R\$)', flex: 2, align: TextAlign.right),
                  _colHeader('Novo Preço (R\$)', flex: 2, align: TextAlign.right),
                  _colHeader('Margem (%)', flex: 2, align: TextAlign.right),
                  _colHeader('Vigência', flex: 2, align: TextAlign.right),
                  // Coluna do botão remover (sem label)
                  const SizedBox(width: 36),
                ],
              ),
            ),

          Expanded(child: TabelaPrecos(controller: controller)),

          if (temDados)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Text(
                'Exibindo ${controller.filtrados.length} de ${controller.materiais.where((m) => !m.removido).length} materiais',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _abrirBuscaMaterial(BuildContext context) async {
    final material = await showModalBottomSheet<MaterialPreco>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => BuscaMaterialSheet(controller: controller),
    );
    if (material != null) {
      controller.adicionarMaterial(material);
    }
  }

  Widget _colHeader(String label, {int flex = 1, TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _numeroBadge(String n) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: _laranja, borderRadius: BorderRadius.circular(6)),
      child: Center(
        child: Text(
          n,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }
}