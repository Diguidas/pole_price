import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/widgets/preco/painel_esquerdo.dart';
import 'package:pole_price/widgets/preco/preco_topbar.dart';

class PrecoScreen extends StatefulWidget {
  final String? draftId;
  const PrecoScreen({super.key, this.draftId});

  @override
  State<PrecoScreen> createState() => _PrecoScreenState();
}

class _PrecoScreenState extends State<PrecoScreen> {
  late final PrecoController controller;

  @override
  void initState() {
    super.initState();
    controller = PrecoController.instance;
    controller.addListener(_rebuild);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.iniciarNovaSessao();
      if (widget.draftId != null) {
        controller.carregarRascunho(widget.draftId!); // ← novo método
      } else {
        controller.buscarDoSap();
      }
    });
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_rebuild);
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
                : controller.erro != null && controller.materiais.isEmpty
                ? _ErroView(
                    mensagem: controller.erro!,
                    onRetry: controller.buscarDoSap,
                  )
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: PainelEsquerdo(controller: controller),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ErroView extends StatelessWidget {
  final String mensagem;
  final VoidCallback onRetry;
  const _ErroView({required this.mensagem, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(mensagem, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}