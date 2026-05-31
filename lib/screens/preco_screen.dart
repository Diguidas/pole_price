import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/widgets/preco/painel_esquerdo.dart';
import 'package:pole_price/widgets/preco/painel_direito.dart';
import 'package:pole_price/widgets/preco/preco_topbar.dart';

class PrecoScreen extends StatefulWidget {
  final String? filtroClusterId;
  final String? filtroClusterNome;

  const PrecoScreen({super.key, this.filtroClusterId, this.filtroClusterNome});

  @override
  State<PrecoScreen> createState() => _PrecoScreenState();
}

class _PrecoScreenState extends State<PrecoScreen> {
  // Usa o singleton — estado preservado ao navegar entre telas.
  late final PrecoController controller;

  @override
  void initState() {
    super.initState();
    controller = PrecoController.instance;
    controller.addListener(_rebuild);
    controller.init().then((_) {
      if (widget.filtroClusterId != null) {
        controller.filtrarPorCluster(widget.filtroClusterId!);
      }
    });
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_rebuild);
    // NÃO chama controller.dispose() — o singleton precisa sobreviver.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Column(
        children: [
          PrecoTopbar(controller: controller),
          Expanded(
            child: controller.loading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: PainelEsquerdo(controller: controller),
                        ),
                        const SizedBox(width: 20),
                        SizedBox(
                          width: 380,
                          child: PainelDireito(controller: controller),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
