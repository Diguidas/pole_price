import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/widgets/preco/seletor_targets.dart';

const _laranja = Color(0xFFFF6B00);

class SecaoListasDestino extends StatelessWidget {
  final PrecoController controller;
  const SecaoListasDestino({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _numeroBadge('2'),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Listas destino',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          OutlinedButton.icon(
            icon: const Icon(Icons.checklist_rtl_outlined, size: 18),
            label: const Text('Selecionar listas em lote'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _laranja,
              side: const BorderSide(color: _laranja),
              minimumSize: const Size.fromHeight(45),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: controller.selecionada == null
                ? null
                : () => abrirSeletorTargets(context, controller),
          ),

          if (controller.targets.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: controller.targets.map((id) {
                final nome = controller.listas
                    .where((l) => l.id == id)
                    .map((l) => l.description)
                    .firstOrNull ?? id;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _laranja.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _laranja.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _laranja,
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => controller.toggleTarget(id),
                        child: const Icon(Icons.close, size: 14, color: _laranja),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'As listas selecionadas receberão os preços da lista mãe conforme as exceções e ajustes configurados abaixo.',
                      style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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