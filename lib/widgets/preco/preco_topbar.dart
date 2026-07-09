import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/screens/definir_aprovacoes_screen.dart';
import 'package:pole_price/widgets/resumo_aprovacao_sheet.dart';
import 'package:pole_price/widgets/app_shell.dart'; // AppShell, AppPage

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
              if (temDados) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'Preços ao vivo · SAP',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B00),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        controller.modo == SapModo.grupo
                            ? 'Grupo ${controller.kdgrp ?? ''}'
                            : 'Lista ${controller.pltyp ?? ''}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else
                Text(
                  'Aguardando busca do SAP',
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

          // ── Botão Query unificado ───────────────────────────────────
          _QueryButton(controller: controller),

          const SizedBox(width: 12),

          // ── Botão Salvar rascunho ───────────────────────────────────
          _SalvarRascunhoButton(controller: controller),

          const SizedBox(width: 8),

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
                    if (controller.vigenciaGlobalDatab == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Informe a vigência global antes de salvar.',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    if (controller.selecionada == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Lista mãe não identificada.'),
                        ),
                      );
                      return;
                    }
                    final result = await showResumoDraft(
                      context: context,
                      listasMae: controller.listas,
                      selecionada: controller.selecionada!,
                      materiais: controller.materiais,
                      targets: controller.targets,
                      regras: controller.regrasEfetivas,
                    );
                    if (result != null && context.mounted) {
                      try {
                        final draftId = await controller.salvar(
                          justificativa: result.justificativa,
                          sapStatus: result.sapStatus,
                        );
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

// ── Botão Salvar rascunho ─────────────────────────────────────────────────────
class _SalvarRascunhoButton extends StatefulWidget {
  final PrecoController controller;
  const _SalvarRascunhoButton({required this.controller});

  @override
  State<_SalvarRascunhoButton> createState() => _SalvarRascunhoButtonState();
}

class _SalvarRascunhoButtonState extends State<_SalvarRascunhoButton> {
  bool _salvando = false;

  @override
  Widget build(BuildContext context) {
    final temDados = widget.controller.materiais.isNotEmpty;

    return OutlinedButton.icon(
      icon: _salvando
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _laranja),
            )
          : const Icon(Icons.save_outlined, size: 18, color: _laranja),
      label: Text(
        _salvando ? 'Salvando...' : 'Salvar rascunho',
        style: const TextStyle(fontSize: 13, color: _laranja),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        side: const BorderSide(color: _laranja),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: (!temDados || _salvando)
          ? null
          : () async {
              if (widget.controller.vigenciaGlobalDatab == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Informe a vigência global antes de salvar.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (widget.controller.selecionada == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lista mãe não identificada.')),
                );
                return;
              }
              setState(() => _salvando = true);
              try {
                final draftId = await widget.controller.salvarRascunho();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Rascunho salvo!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  AppShell.of(
                    context,
                  ).goTo(AppPage.rascunhos); // ← ir para rascunhos
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao salvar rascunho: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _salvando = false);
              }
            },
    );
  }
}

// ── Botão Query unificado ─────────────────────────────────────────────────────
class _QueryButton extends StatelessWidget {
  final PrecoController controller;
  const _QueryButton({required this.controller});

  bool get _temFiltros =>
      controller.datab != null ||
      controller.datbi != null ||
      controller.kznepFilter != null ||
      controller.loevmFilter != null;

  int get _contFiltros {
    int c = 0;
    if (controller.datab != null) c++;
    if (controller.datbi != null) c++;
    if (controller.kznepFilter != null) c++;
    if (controller.loevmFilter != null) c++;
    return c;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        OutlinedButton.icon(
          icon: controller.loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _laranja,
                  ),
                )
              : Icon(
                  Icons.tune,
                  size: 18,
                  color: _temFiltros ? _laranja : Colors.grey.shade600,
                ),
          label: Text(
            controller.loading ? 'Buscando...' : 'Query',
            style: TextStyle(
              fontSize: 13,
              color: _temFiltros ? _laranja : Colors.grey.shade700,
              fontWeight: _temFiltros ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            side: BorderSide(
              color: _temFiltros ? _laranja : Colors.grey.shade300,
            ),
          ),
          onPressed: controller.loading
              ? null
              : () async {
                  final result = await showDialog<_QueryResult?>(
                    context: context,
                    builder: (_) => _QueryFilterDialog(controller: controller),
                  );
                  if (result == null || !context.mounted) return;
                  // Aplica no controller
                  controller.datab = result.datab;
                  controller.databOp = result.databOp;
                  controller.datbi = result.datbi;
                  controller.datbiOp = result.datbiOp;
                  controller.kznepFilter = result.kznepFilter;
                  controller.loevmFilter = result.loevmFilter;
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
        if (_temFiltros)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: _laranja,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$_contFiltros',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Resultado do dialog de query ──────────────────────────────────────────────
class _QueryResult {
  final DateTime? datab;
  final String? databOp;
  final DateTime? datbi;
  final String? datbiOp;
  final String? kznepFilter;
  final String? loevmFilter;

  const _QueryResult({
    this.datab,
    this.databOp,
    this.datbi,
    this.datbiOp,
    this.kznepFilter,
    this.loevmFilter,
  });
}

// ── Dialog de Query unificado ─────────────────────────────────────────────────
class _QueryFilterDialog extends StatefulWidget {
  final PrecoController controller;
  const _QueryFilterDialog({required this.controller});

  @override
  State<_QueryFilterDialog> createState() => _QueryFilterDialogState();
}

class _QueryFilterDialogState extends State<_QueryFilterDialog> {
  late DateTime? _datab;
  late String _databOp;
  late DateTime? _datbi;
  late String _datbiOp;
  late String? _kznepFilter;
  late String? _loevmFilter;

  late final TextEditingController _databCtrl;
  late final TextEditingController _datbiCtrl;
  String? _erroDatab;
  String? _erroDatbi;

  static const _dateOps = [
    ('GE', '>=', 'A partir de'),
    ('LE', '<=', 'Até'),
    ('EQ', '=', 'Igual a'),
    ('NE', '<>', 'Diferente de'),
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _datab = c.datab;
    _databOp = c.databOp ?? 'GE';
    _datbi = c.datbi;
    _datbiOp = c.datbiOp ?? 'LE';
    _kznepFilter = c.kznepFilter;
    _loevmFilter = c.loevmFilter;

    _databCtrl = TextEditingController(text: _dtToStr(_datab));
    _datbiCtrl = TextEditingController(text: _dtToStr(_datbi));
  }

  @override
  void dispose() {
    _databCtrl.dispose();
    _datbiCtrl.dispose();
    super.dispose();
  }

  String _dtToStr(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }

  DateTime? _parseDate(String text) {
    final parts = text.split('/');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    if (d < 1 || d > 31 || m < 1 || m > 12 || y < 1000) return null;
    return DateTime(y, m, d);
  }

  void _confirmar() {
    final databText = _databCtrl.text.trim();
    final datbiText = _datbiCtrl.text.trim();

    DateTime? datab = databText.isEmpty ? null : _parseDate(databText);
    DateTime? datbi = datbiText.isEmpty ? null : _parseDate(datbiText);

    if (databText.isNotEmpty && datab == null) {
      setState(() => _erroDatab = 'Data inválida. Use DD/MM/AAAA.');
      return;
    }
    if (datbiText.isNotEmpty && datbi == null) {
      setState(() => _erroDatbi = 'Data inválida. Use DD/MM/AAAA.');
      return;
    }

    Navigator.pop(
      context,
      _QueryResult(
        datab: datab,
        databOp: datab != null ? _databOp : null,
        datbi: datbi,
        datbiOp: datbi != null ? _datbiOp : null,
        kznepFilter: _kznepFilter,
        loevmFilter: _loevmFilter,
      ),
    );
  }

  InputDecoration _inputDec(String hint, String? erro) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade400, letterSpacing: 0),
    errorText: erro,
    prefixIcon: const Icon(
      Icons.edit_calendar_outlined,
      size: 18,
      color: _laranja,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: _laranja, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.red.shade300),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
    ),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  );

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Color(0xFF475569),
      ),
    ),
  );

  Widget _opSelector(String current, ValueChanged<String> onSelect) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _dateOps.map((op) {
        final (code, symbol, desc) = op;
        final sel = current == code;
        return InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () => setState(() => onSelect(code)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: sel ? _laranja : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: sel ? _laranja : Colors.grey.shade200),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  symbol,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: sel ? Colors.white : Colors.grey.shade700,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 9,
                    color: sel ? Colors.white70 : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _statusSelector({
    required String label,
    required IconData icon,
    required String? value,
    required ValueChanged<String?> onChanged,
    required String sapField,
  }) {
    final opts = [
      (null, 'Todos', Icons.all_inclusive, 'Sem filtro'),
      ('X', 'Apenas $label', Icons.filter_alt_outlined, '$sapField = marcado'),
      ('E', 'Excluir $label', Icons.block, '$sapField ≠ marcado'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: opts.map((opt) {
        final (v, lbl, ic, sub) = opt;
        final sel = value == v;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => onChanged(v)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: sel ? _laranja.withOpacity(0.07) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: sel ? _laranja : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    ic,
                    size: 16,
                    color: sel ? _laranja : Colors.grey.shade500,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lbl,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: sel ? _laranja : Colors.grey.shade800,
                          ),
                        ),
                        Text(
                          sub,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (sel) const Icon(Icons.check, size: 14, color: _laranja),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 18, color: _laranja),
                  const SizedBox(width: 10),
                  const Text(
                    'Filtros da consulta SAP',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.grey.shade500,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Body com scroll
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Vigência início ──────────────────────────────
                    _sectionTitle('DATA INÍCIO (datab)'),
                    _opSelector(_databOp, (v) => _databOp = v),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _databCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_DateMaskFormatter()],
                      style: const TextStyle(fontSize: 14, letterSpacing: 1),
                      decoration: _inputDec(
                        'DD/MM/AAAA (opcional)',
                        _erroDatab,
                      ),
                      onChanged: (_) {
                        if (_erroDatab != null)
                          setState(() => _erroDatab = null);
                      },
                    ),

                    const SizedBox(height: 20),
                    Divider(color: Colors.grey.shade100),
                    const SizedBox(height: 16),

                    // ── Vigência fim ─────────────────────────────────
                    _sectionTitle('DATA FIM (datbi)'),
                    _opSelector(_datbiOp, (v) => _datbiOp = v),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _datbiCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_DateMaskFormatter()],
                      style: const TextStyle(fontSize: 14, letterSpacing: 1),
                      decoration: _inputDec(
                        'DD/MM/AAAA (opcional)',
                        _erroDatbi,
                      ),
                      onChanged: (_) {
                        if (_erroDatbi != null)
                          setState(() => _erroDatbi = null);
                      },
                    ),

                    const SizedBox(height: 20),
                    Divider(color: Colors.grey.shade100),
                    const SizedBox(height: 16),

                    // ── Inativo ──────────────────────────────────────
                    _sectionTitle('INATIVO (KZNEP)'),
                    _statusSelector(
                      label: 'Inativo',
                      icon: Icons.pause_circle_outline,
                      value: _kznepFilter,
                      sapField: 'KZNEP = I',
                      onChanged: (v) => _kznepFilter = v,
                    ),

                    const SizedBox(height: 16),
                    Divider(color: Colors.grey.shade100),
                    const SizedBox(height: 16),

                    // ── Bloqueado ────────────────────────────────────
                    _sectionTitle('BLOQUEADO (LOEVM_KO)'),
                    _statusSelector(
                      label: 'Bloqueado',
                      icon: Icons.lock_outline,
                      value: _loevmFilter,
                      sapField: 'LOEVM_KO = X',
                      onChanged: (v) => _loevmFilter = v,
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _databCtrl.clear();
                        _datbiCtrl.clear();
                        _databOp = 'GE';
                        _datbiOp = 'LE';
                        _kznepFilter = null;
                        _loevmFilter = null;
                        _erroDatab = null;
                        _erroDatbi = null;
                      });
                    },
                    child: Text(
                      'Limpar tudo',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancelar',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text(
                      'Buscar do SAP',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _laranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _confirmar,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widget interno: seletor de range de datas ─────────────────────────────────
// ── Botão de filtro de status (inativo/bloqueado) ────────────────────────────
class _StatusFilterButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value; // null=todos, 'X'=apenas marcados, 'E'=excluir marcados
  final ValueChanged<String?> onChanged;

  const _StatusFilterButton({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  String _currentLabel() {
    return switch (value) {
      'X' => '$label: apenas',
      'E' => '$label: excluir',
      _ => label,
    };
  }

  Color _color() {
    return switch (value) {
      'X' => Colors.orange.shade700,
      'E' => Colors.red.shade400,
      _ => Colors.grey.shade600,
    };
  }

  BorderSide _border() {
    return switch (value) {
      'X' => BorderSide(color: Colors.orange.shade400),
      'E' => BorderSide(color: Colors.red.shade300),
      _ => BorderSide(color: Colors.grey.shade300),
    };
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 15, color: _color()),
      label: Text(
        _currentLabel(),
        style: TextStyle(fontSize: 12, color: _color()),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: _border(),
      ),
      onPressed: () async {
        final result = await showDialog<String?>(
          context: context,
          builder: (_) => _StatusFilterDialog(label: label, current: value),
        );
        // result == '__clear__' significa "limpar", result == null = cancelou
        if (result == '__clear__') {
          onChanged(null);
        } else if (result != null) {
          onChanged(result);
        }
      },
    );
  }
}

class _StatusFilterDialog extends StatelessWidget {
  final String label;
  final String? current;
  const _StatusFilterDialog({required this.label, this.current});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Filtro: $label'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Como tratar materiais marcados como "$label" na lista?',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          _option(
            context,
            value: null,
            label: 'Todos (sem filtro)',
            sub: 'Retorna marcados e não marcados',
            icon: Icons.all_inclusive,
          ),
          const SizedBox(height: 8),
          _option(
            context,
            value: 'X',
            label: 'Apenas $label',
            sub: 'Retorna somente os marcados como $label',
            icon: Icons.filter_alt_outlined,
          ),
          const SizedBox(height: 8),
          _option(
            context,
            value: 'E',
            label: 'Excluir $label',
            sub: 'Oculta os marcados como $label',
            icon: Icons.block,
          ),
          const SizedBox(height: 16),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, '__clear__'),
          child: Text('Limpar', style: TextStyle(color: Colors.grey.shade500)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _option(
    BuildContext context, {
    required String? value,
    required String label,
    required String sub,
    required IconData icon,
  }) {
    final selected = current == value;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.pop(context, value ?? '__clear__'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFF6B00).withOpacity(0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFFFF6B00) : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? const Color(0xFFFF6B00) : Colors.grey.shade500,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: selected
                          ? const Color(0xFFFF6B00)
                          : Colors.grey.shade800,
                    ),
                  ),
                  Text(
                    sub,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 16, color: Color(0xFFFF6B00)),
          ],
        ),
      ),
    );
  }
}

// ── Resultado do seletor de data ──────────────────────────────────────────────
class _DateResult {
  final DateTime date;
  final String sapOp;
  const _DateResult({required this.date, required this.sapOp});
}

// ── Máscara de data dd/MM/yyyy ────────────────────────────────────────────────
class _DateMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// ── Dialog de filtro de data (sem calendário) ─────────────────────────────────
class _DateFilterDialog extends StatefulWidget {
  final String label;
  final DateTime? initialDate;
  final String? initialSapOp;

  const _DateFilterDialog({
    required this.label,
    this.initialDate,
    this.initialSapOp,
  });

  @override
  State<_DateFilterDialog> createState() => _DateFilterDialogState();
}

class _DateFilterDialogState extends State<_DateFilterDialog> {
  late final TextEditingController _ctrl;
  late String _sapOp;
  String? _erro;

  static const _ops = [
    ('GE', '>=', 'A partir de'),
    ('LE', '<=', 'Até'),
    ('EQ', '=', 'Exatamente'),
    ('NE', '<>', 'Diferente de'),
  ];

  @override
  void initState() {
    super.initState();
    _sapOp = widget.initialSapOp ?? 'GE';
    final dt = widget.initialDate;
    _ctrl = TextEditingController(
      text: dt != null
          ? '${dt.day.toString().padLeft(2, '0')}/'
                '${dt.month.toString().padLeft(2, '0')}/'
                '${dt.year}'
          : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  DateTime? _parse(String text) {
    final parts = text.split('/');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    if (d < 1 || d > 31 || m < 1 || m > 12 || y < 1000) return null;
    return DateTime(y, m, d);
  }

  void _confirm() {
    final dt = _parse(_ctrl.text);
    if (dt == null) {
      setState(() => _erro = 'Data inválida. Use dd/MM/aaaa.');
      return;
    }
    Navigator.pop(context, _DateResult(date: dt, sapOp: _sapOp));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: _laranja,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              const Text(
                'Operador',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF555555),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _ops.map((op) {
                  final (sapCode, symbol, desc) = op;
                  final selected = _sapOp == sapCode;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _sapOp = sapCode),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? _laranja : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? _laranja : Colors.grey.shade200,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            symbol,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: selected
                                  ? Colors.white
                                  : Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            desc,
                            style: TextStyle(
                              fontSize: 10,
                              color: selected
                                  ? Colors.white70
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),

              const Text(
                'Data',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF555555),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [_DateMaskFormatter()],
                style: const TextStyle(fontSize: 15, letterSpacing: 1),
                decoration: InputDecoration(
                  hintText: 'dd/MM/aaaa',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    letterSpacing: 0,
                  ),
                  errorText: _erro,
                  prefixIcon: const Icon(
                    Icons.edit_calendar_outlined,
                    size: 18,
                    color: _laranja,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _laranja, width: 1.5),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.red.shade300),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Colors.red.shade400,
                      width: 1.5,
                    ),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                onChanged: (_) {
                  if (_erro != null) setState(() => _erro = null);
                },
                onSubmitted: (_) => _confirm(),
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.initialDate != null)
                    TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: Text(
                        'Limpar',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancelar',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _laranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Aplicar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Botão + Dialog de Vigência Global ────────────────────────────────────────
class VigenciaGlobalButton extends StatelessWidget {
  final PrecoController controller;
  const VigenciaGlobalButton({required this.controller});

  String get _label {
    final de = controller.vigenciaGlobalDatab;
    final ate = controller.vigenciaGlobalDatbi;
    if (de == null && ate == null) return 'Vigência';
    if (de != null && ate != null) return '$de → $ate';
    if (de != null) return 'De $de';
    return 'Até $ate';
  }

  bool get _ativo =>
      controller.vigenciaGlobalDatab != null ||
      controller.vigenciaGlobalDatbi != null;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(
        Icons.date_range_outlined,
        size: 15,
        color: _ativo ? _laranja : Colors.grey.shade600,
      ),
      label: Text(
        _label,
        style: TextStyle(
          fontSize: 12,
          color: _ativo ? _laranja : Colors.grey.shade600,
          fontWeight: _ativo ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: _ativo ? _laranja : Colors.grey.shade300),
      ),
      onPressed: () async {
        final result = await showDialog<_VigenciaResult?>(
          context: context,
          builder: (_) => _VigenciaGlobalDialog(
            initialDatab: controller.vigenciaGlobalDatab,
            initialDatbi: controller.vigenciaGlobalDatbi,
          ),
        );
        if (result == null) return; // cancelou
        controller.vigenciaGlobalDatab = result.datab;
        controller.vigenciaGlobalDatbi = result.datbi;
        // ignore: invalid_use_of_protected_member
        controller.notifyListeners();
      },
    );
  }
}

class _VigenciaResult {
  final String? datab;
  final String? datbi;
  const _VigenciaResult({this.datab, this.datbi});
}

class _VigenciaGlobalDialog extends StatefulWidget {
  final String? initialDatab;
  final String? initialDatbi;
  const _VigenciaGlobalDialog({this.initialDatab, this.initialDatbi});

  @override
  State<_VigenciaGlobalDialog> createState() => _VigenciaGlobalDialogState();
}

class _VigenciaGlobalDialogState extends State<_VigenciaGlobalDialog> {
  late final TextEditingController _databCtrl;
  late final TextEditingController _datbiCtrl;
  String? _erroDatab;
  String? _erroDatbi;

  @override
  void initState() {
    super.initState();
    _databCtrl = TextEditingController(text: widget.initialDatab ?? '');
    _datbiCtrl = TextEditingController(text: widget.initialDatbi ?? '');
  }

  @override
  void dispose() {
    _databCtrl.dispose();
    _datbiCtrl.dispose();
    super.dispose();
  }

  bool _validarData(String text) {
    if (text.isEmpty) return true; // opcional
    final parts = text.split('/');
    if (parts.length != 3) return false;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return false;
    if (d < 1 || d > 31 || m < 1 || m > 12 || y < 1000) return false;
    return true;
  }

  void _confirmar() {
    final de = _databCtrl.text.trim();
    final ate = _datbiCtrl.text.trim();

    final erroDatab = (de.isNotEmpty && !_validarData(de))
        ? 'Data inválida. Use DD/MM/AAAA.'
        : null;
    final erroDatbi = (ate.isNotEmpty && !_validarData(ate))
        ? 'Data inválida. Use DD/MM/AAAA.'
        : null;

    if (erroDatab != null || erroDatbi != null) {
      setState(() {
        _erroDatab = erroDatab;
        _erroDatbi = erroDatbi;
      });
      return;
    }

    Navigator.pop(
      context,
      _VigenciaResult(
        datab: de.isEmpty ? null : de,
        datbi: ate.isEmpty ? null : ate,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, String? erro) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, letterSpacing: 0),
      errorText: erro,
      prefixIcon: const Icon(
        Icons.edit_calendar_outlined,
        size: 18,
        color: _laranja,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _laranja, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Título
              Row(
                children: [
                  const Icon(
                    Icons.date_range_outlined,
                    size: 18,
                    color: _laranja,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Vigência Global',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Define o período de validade aplicado a todos os itens ao salvar.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),

              // Campo De
              const Text(
                'De (início)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF555555),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _databCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [_DateMaskFormatter()],
                style: const TextStyle(fontSize: 15, letterSpacing: 1),
                decoration: _inputDecoration('DD/MM/AAAA', _erroDatab),
                onChanged: (_) {
                  if (_erroDatab != null) setState(() => _erroDatab = null);
                },
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              ),

              const SizedBox(height: 16),

              // Campo Até
              const Text(
                'Até (fim)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF555555),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _datbiCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [_DateMaskFormatter()],
                style: const TextStyle(fontSize: 15, letterSpacing: 1),
                decoration: _inputDecoration('DD/MM/AAAA', _erroDatbi),
                onChanged: (_) {
                  if (_erroDatbi != null) setState(() => _erroDatbi = null);
                },
                onSubmitted: (_) => _confirmar(),
              ),

              const SizedBox(height: 24),

              // Ações
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.initialDatab != null ||
                      widget.initialDatbi != null)
                    TextButton(
                      onPressed: () => Navigator.pop(
                        context,
                        const _VigenciaResult(datab: null, datbi: null),
                      ),
                      child: Text(
                        'Limpar',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancelar',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _confirmar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _laranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Aplicar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Seletor de range de datas ─────────────────────────────────────────────────
class _DateRangePicker extends StatelessWidget {
  final PrecoController controller;
  const _DateRangePicker({required this.controller});

  String _label(DateTime? dt, String? op, String fallback) {
    if (dt == null) return fallback;
    final symbol = switch (op) {
      'GE' => '>=',
      'LE' => '<=',
      'EQ' => '=',
      'NE' => '<>',
      _ => '>=',
    };
    final d =
        '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
    return '$symbol $d';
  }

  Future<void> _openDialog(
    BuildContext context, {
    required String label,
    required DateTime? current,
    required String? currentOp,
    required void Function(DateTime date, String sapOp) onConfirm,
    required VoidCallback onClear,
  }) async {
    final result = await showDialog<_DateResult?>(
      context: context,
      builder: (ctx) => _DateFilterDialog(
        label: label,
        initialDate: current,
        initialSapOp: currentOp,
      ),
    );
    if (result == null && current != null) {
      onClear();
    } else if (result != null) {
      onConfirm(result.date, result.sapOp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ativoDe = controller.datab != null;
    final ativoAte = controller.datbi != null;

    return Row(
      children: [
        _dateButton(
          label: 'De: ${_label(controller.datab, controller.databOp, 'Hoje')}',
          ativo: ativoDe,
          onTap: () => _openDialog(
            context,
            label: 'Data início (datab)',
            current: controller.datab,
            currentOp: controller.databOp,
            onConfirm: (date, sapOp) {
              controller.datab = date;
              controller.databOp = sapOp;
              // ignore: invalid_use_of_protected_member
              controller.notifyListeners();
            },
            onClear: () {
              controller.datab = null;
              controller.databOp = null;
              // ignore: invalid_use_of_protected_member
              controller.notifyListeners();
            },
          ),
        ),
        const SizedBox(width: 8),
        _dateButton(
          label:
              'Até: ${_label(controller.datbi, controller.datbiOp, 'Aberto')}',
          ativo: ativoAte,
          onTap: () => _openDialog(
            context,
            label: 'Data fim (datbi)',
            current: controller.datbi,
            currentOp: controller.datbiOp,
            onConfirm: (date, sapOp) {
              controller.datbi = date;
              controller.datbiOp = sapOp;
              // ignore: invalid_use_of_protected_member
              controller.notifyListeners();
            },
            onClear: () {
              controller.datbi = null;
              controller.datbiOp = null;
              // ignore: invalid_use_of_protected_member
              controller.notifyListeners();
            },
          ),
        ),
      ],
    );
  }

  Widget _dateButton({
    required String label,
    required bool ativo,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: ativo ? _laranja : Colors.grey.shade300),
        foregroundColor: ativo ? _laranja : Colors.grey.shade700,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: ativo ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}
