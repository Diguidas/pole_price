import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/widgets/tabela_precos.dart';
import 'package:pole_price/widgets/preco/seletor_lista_mae.dart';

const _laranja = Color(0xFFFF6B00);

class PainelEsquerdo extends StatelessWidget {
  final PrecoController controller;
  const PainelEsquerdo({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
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
                      'Lista mãe (base)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: () => abrirSeletorListaMae(context, controller),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.table_chart_outlined, color: _laranja),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            controller.selecionada != null
                                ? controller.selecionada!.description
                                : 'Clique para pesquisar e selecionar a lista...',
                            style: TextStyle(
                              color: controller.selecionada != null
                                  ? Colors.black87
                                  : Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      ],
                    ),
                  ),
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

          if (controller.selecionada != null)
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
                ],
              ),
            ),

          Expanded(child: TabelaPrecos(controller: controller)),

          if (controller.selecionada != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Text(
                'Exibindo ${controller.filtrados.length} de ${controller.materiais.length} materiais',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
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