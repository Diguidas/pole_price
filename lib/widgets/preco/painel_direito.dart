import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/widgets/preco/secao_listas_destino.dart';
import 'package:pole_price/widgets/preco/secao_excecoes.dart';

class PainelDireito extends StatelessWidget {
  final PrecoController controller;
  const PainelDireito({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SecaoListasDestino(controller: controller),
          const SizedBox(height: 16),
          SecaoExcecoes(controller: controller),
        ],
      ),
    );
  }
}