import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/material_preco.dart';

const _laranja = Color(0xFFFF6B00);

// ── Botão "Limites SAP" (geral, por agrupamento) ──────────────────────────────
class LimitesSapAgrupamentoButton extends StatelessWidget {
  final PrecoController controller;
  const LimitesSapAgrupamentoButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final temDados = controller.materiais.isNotEmpty;

    return OutlinedButton.icon(
      icon: Icon(
        Icons.rule_rounded,
        size: 18,
        color: temDados ? _laranja : Colors.grey.shade400,
      ),
      label: Text(
        'Limites SAP',
        style: TextStyle(
          fontSize: 13,
          color: temDados ? _laranja : Colors.grey.shade400,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: temDados ? _laranja : Colors.grey.shade300),
      ),
      onPressed: !temDados
          ? null
          : () => showDialog(
                context: context,
                builder: (_) => _LimitesSapAgrupamentoDialog(controller: controller),
              ),
    );
  }
}

// ── Dialog: seleciona o agrupamento, depois informa % para baixo/cima ─────────
class _LimitesSapAgrupamentoDialog extends StatefulWidget {
  final PrecoController controller;
  const _LimitesSapAgrupamentoDialog({required this.controller});

  @override
  State<_LimitesSapAgrupamentoDialog> createState() =>
      _LimitesSapAgrupamentoDialogState();
}

class _LimitesSapAgrupamentoDialogState
    extends State<_LimitesSapAgrupamentoDialog> {
  late final Map<String, List<MaterialPreco>> _grupos;
  late final List<String> _ordem;

  String? _agrupamentoSelecionado;
  final _menosCtrl = TextEditingController();
  final _maisCtrl = TextEditingController();
  String? _erro;

  @override
  void initState() {
    super.initState();
    _grupos = widget.controller.materiaisPorAgrupamento;
    _ordem = _grupos.keys.toList();
    if (_ordem.length == 1) _selecionar(_ordem.first);
  }

  @override
  void dispose() {
    _menosCtrl.dispose();
    _maisCtrl.dispose();
    super.dispose();
  }

  void _selecionar(String? agrupamento) {
    setState(() {
      _agrupamentoSelecionado = agrupamento;
      _erro = null;
      final atual = agrupamento == null
          ? null
          : widget.controller.percentuaisPorAgrupamento[agrupamento];
      _menosCtrl.text = atual?.menos != null
          ? atual!.menos!.toStringAsFixed(1).replaceAll('.', ',')
          : '';
      _maisCtrl.text = atual?.mais != null
          ? atual!.mais!.toStringAsFixed(1).replaceAll('.', ',')
          : '';
    });
  }

  double? _parse(String v) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return double.tryParse(s.replaceAll(',', '.'));
  }

  void _confirmar() {
    final agrupamento = _agrupamentoSelecionado;
    if (agrupamento == null) return;
    final menos = _parse(_menosCtrl.text);
    final mais = _parse(_maisCtrl.text);
    if ((menos == null) != (mais == null)) {
      setState(() {
        _erro = 'Preencha os dois (para baixo e para cima) ou deixe os dois em branco.';
      });
      return;
    }
    widget.controller.aplicarLimitesPorAgrupamento({
      agrupamento: (menos: menos, mais: mais),
    });
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Limites SAP aplicados ao agrupamento "$agrupamento".'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final materiaisDoGrupo = _agrupamentoSelecionado == null
        ? const <MaterialPreco>[]
        : _grupos[_agrupamentoSelecionado]!;
    final travados =
        materiaisDoGrupo.where((m) => m.mxwrtGkwrtManual == true).length;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.rule_rounded, size: 18, color: _laranja),
          SizedBox(width: 10),
          Text('Limites SAP por agrupamento', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _agrupamentoSelecionado,
              decoration: const InputDecoration(
                labelText: 'Agrupamento',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _ordem
                  .map((a) => DropdownMenuItem(value: a, child: Text(a, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: _selecionar,
            ),
            if (_agrupamentoSelecionado != null) ...[
              const SizedBox(height: 6),
              Text(
                travados > 0
                    ? '${materiaisDoGrupo.length} materiais · $travados travados manualmente'
                    : '${materiaisDoGrupo.length} materiais',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _menosCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '% para baixo',
                        hintText: 'Vazio = 0,00',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maisCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '% para cima',
                        hintText: 'Vazio = 0,00',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Aplicado sobre o PPV CX de cada material do agrupamento, gerando o '
                'MXWRT/GKWRT (VK11). Se deixar os dois em branco, o limite é removido. '
                'Materiais travados manualmente (ícone na linha da tabela) não são afetados.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(_erro!, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _agrupamentoSelecionado == null ? null : _confirmar,
          style: FilledButton.styleFrom(backgroundColor: _laranja),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
