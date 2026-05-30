import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/screens/definir_aprovacoes_screen.dart';
import 'package:pole_price/widgets/resumo_aprovacao_sheet.dart';

const _laranja = Color(0xFFFF6B00);

class PrecoTopbar extends StatelessWidget {
  final PrecoController controller;
  const PrecoTopbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gestão de Preços',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                controller.selecionada != null
                    ? 'Preço atual · Supabase (tabela materials)'
                    : 'Selecione uma lista · dados do Supabase',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
          const Spacer(),
          if (controller.selecionada != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 22),
              tooltip: 'Recarregar preços do Supabase',
              onPressed: controller.loading
                  ? null
                  : () async {
                      await controller.recarregarMateriais();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Preços recarregados do Supabase.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
            ),
          OutlinedButton.icon(
            icon: controller.syncingSap
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync, size: 18),
            label: Text(controller.syncingSap ? 'Sincronizando...' : 'Buscar do SAP'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _laranja,
              side: const BorderSide(color: _laranja),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: controller.syncingSap
                ? null
                : () async {
                    try {
                      final result = await controller.atualizarDoSap();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              result.mensagem ??
                                  '${result.materiaisAtualizados} material(is) atualizado(s) do SAP.',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erro ao sincronizar SAP: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Salvar para aprovação'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _laranja,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: controller.selecionada == null
                ? null
                : () async {
                    final confirm = await showResumoDraft(
                      context: context,
                      listasMae: controller.listas,
                      selecionada: controller.selecionada!,
                      materiais: controller.materiais,
                      targets: controller.targets,
                      regras: controller.regras,
                    );
                    if (confirm == true && context.mounted) {
                      try {
                        final draftId = await controller.salvar();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Rascunho enviado! Abrindo tela de aprovações...'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AprovacoesScreen(draftIdInicial: draftId),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Erro ao salvar: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
          ),
        ],
      ),
    );
  }
}