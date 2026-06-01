import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/screens/definir_aprovacoes_screen.dart';
import 'package:pole_price/widgets/resumo_aprovacao_sheet.dart';
import 'package:pole_price/widgets/app_shell.dart'; // DateFilterDialog, DateFilter, DateOp

const _laranja = Color(0xFFFF6B00);

class PrecoTopbar extends StatelessWidget {
  final PrecoController controller;
  const PrecoTopbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final temDados = controller.materiais.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          // ── Título + subtítulo ──────────────────────────────────────
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gestão de Preços',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                temDados
                    ? 'Preços ao vivo · SAP (${controller.modo == SapModo.grupo ? 'grupo ${controller.kdgrp}' : 'lista ${controller.pltyp}'})'
                    : 'Aguardando busca do SAP',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),

          const Spacer(),

          // ── Seletor de grupo (apenas no modo Lista+Grupo) ───────────
          if (controller.modo == SapModo.grupo) ...[
            SizedBox(
              width: 140,
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Grupo (kdgrp)',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (v) {
                  controller.kdgrp = v.trim().isEmpty ? null : v.trim();
                },
                controller: TextEditingController(text: controller.kdgrp ?? ''),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // ── Seletor de datas (datab / datbi) ────────────────────────
          _DateRangePicker(controller: controller),

          const SizedBox(width: 12),

          // ── Botão Buscar do SAP ─────────────────────────────────────
          OutlinedButton.icon(
            icon: controller.loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync, size: 18),
            label: Text(controller.loading ? 'Buscando...' : 'Buscar do SAP'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _laranja,
              side: const BorderSide(color: _laranja),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: controller.loading
                ? null
                : () async {
                    try {
                      await controller.buscarDoSap();
                      if (context.mounted && controller.erro != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(controller.erro!),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erro ao buscar do SAP: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
          ),

          const SizedBox(width: 12),

          // ── Botão Salvar para aprovação ─────────────────────────────
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Salvar para aprovação'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _laranja,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: !temDados
                ? null
                : () async {
                    if (controller.selecionada == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Lista mãe não identificada.'),
                        ),
                      );
                      return;
                    }
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
                              content: Text(
                                'Rascunho enviado! Abrindo tela de aprovações...',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                          AppShell.of(
                            context,
                          ).goTo(AppPage.aprovacoes, draftId: draftId);
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

// ── Widget interno: seletor de range de datas ─────────────────────────────────
class _DateRangePicker extends StatelessWidget {
  final PrecoController controller;
  const _DateRangePicker({required this.controller});

  String _label(DateTime? dt, String? op, String fallback) {
    if (dt == null) return fallback;
    final opLabel = _opLabel(op);
    final d =
        '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
    return '$opLabel $d';
  }

  String _opLabel(String? sapOp) {
    return switch (sapOp) {
      'GE' => '>=',
      'LE' => '<=',
      'EQ' => '=',
      'NE' => '<>',
      _ => '>=',
    };
  }

  DateOp _toDateOp(String? sapOp) {
    return switch (sapOp) {
      'GE' => DateOp.gte,
      'LE' => DateOp.lte,
      'EQ' => DateOp.eq,
      'NE' => DateOp.neq,
      _ => DateOp.gte,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _dateButton(
          context,
          label: 'De: ${_label(controller.datab, controller.databOp, 'Hoje')}',
          onTap: () async {
            final result = await showDialog<DateFilter>(
              context: context,
              builder: (_) => DateFilterDialog(
                initial: controller.datab != null
                    ? DateFilter(
                        op: _toDateOp(controller.databOp),
                        date: controller.datab!,
                      )
                    : null,
                label: 'Data início (datab)',
              ),
            );
            if (result != null) {
              controller.datab = result.date;
              controller.databOp = result.op.sapOp;
              // ignore: invalid_use_of_protected_member
              controller.notifyListeners();
            }
          },
        ),
        const SizedBox(width: 8),
        _dateButton(
          context,
          label:
              'Até: ${_label(controller.datbi, controller.datbiOp, 'Aberto')}',
          onTap: () async {
            final result = await showDialog<DateFilter>(
              context: context,
              builder: (_) => DateFilterDialog(
                initial: controller.datbi != null
                    ? DateFilter(
                        op: _toDateOp(controller.datbiOp),
                        date: controller.datbi!,
                      )
                    : null,
                label: 'Data fim (datbi)',
              ),
            );
            if (result != null) {
              controller.datbi = result.date;
              controller.datbiOp = result.op.sapOp;
              // ignore: invalid_use_of_protected_member
              controller.notifyListeners();
            }
          },
        ),
      ],
    );
  }

  Widget _dateButton(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: Colors.grey.shade300),
        foregroundColor: Colors.grey.shade700,
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
