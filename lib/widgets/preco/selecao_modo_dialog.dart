import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/pricelist_model.dart';
import 'package:pole_price/screens/preco_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum DateOp { eq, gte, lte, neq }

extension DateOpExt on DateOp {
  String get label => switch (this) {
        DateOp.eq  => '=',
        DateOp.gte => '>=',
        DateOp.lte => '<=',
        DateOp.neq => '<>',
      };
  String get sapOp => switch (this) {
        DateOp.eq  => 'EQ',
        DateOp.gte => 'GE',
        DateOp.lte => 'LE',
        DateOp.neq => 'NE',
      };
  String get description => switch (this) {
        DateOp.eq  => 'igual a',
        DateOp.gte => 'maior ou igual',
        DateOp.lte => 'menor ou igual',
        DateOp.neq => 'diferente de',
      };
}

class _DateFilter {
  final DateOp op;
  final DateTime date;
  const _DateFilter({required this.op, required this.date});
}

// Máscara DD/MM/AAAA sem dependência externa
class _DateMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue next) {
    final digits = next.text.replaceAll(RegExp(r'\D'), '');
    final buf = StringBuffer();
    for (var i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

const _laranja = Color(0xFFFF6B00);

Future<void> abrirSelecaoModo(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _SelecaoModoSheet(),
  );
}

class _SelecaoModoSheet extends StatefulWidget {
  const _SelecaoModoSheet();

  @override
  State<_SelecaoModoSheet> createState() => _SelecaoModoSheetState();
}

class _SelecaoModoSheetState extends State<_SelecaoModoSheet> {
  final _supabase = Supabase.instance.client;

  SapModo _modo = SapModo.lista;
  List<PriceList> _listas = [];
  PriceList? _listaSelecionada;
  String? _kdgrp;
  _DateFilter _datab = _DateFilter(op: DateOp.gte, date: DateTime.now());
  _DateFilter? _datbi;

  bool _loadingListas = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarListas();
  }

  Future<void> _carregarListas() async {
    setState(() => _loadingListas = true);
    try {
      final res = await _supabase
          .from('price_lists')
          .select('pltyp, ptext')
          .order('ptext');
      setState(() {
        _listas = (res as List).map((e) => PriceList.fromJson(e)).toList();
      });
    } catch (e) {
      setState(() => _erro = 'Erro ao carregar listas: $e');
    } finally {
      setState(() => _loadingListas = false);
    }
  }

  bool get _podeConfirmar {
    if (_listaSelecionada == null) return false;
    if (_modo == SapModo.grupo && (_kdgrp == null || _kdgrp!.isEmpty))
      return false;
    return true;
  }

  void _confirmar() {
    if (!_podeConfirmar) return;

    final controller = PrecoController.instance;
    controller.modo     = _modo;
    controller.pltyp    = _listaSelecionada!.id;
    controller.kdgrp    = _modo == SapModo.grupo ? _kdgrp : null;
    controller.datab    = _datab.date;
    controller.datbi    = _datbi?.date;
    controller.databOp  = _datab.op.sapOp;
    controller.datbiOp  = _datbi?.op.sapOp;

    Navigator.of(context).pop();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PrecoScreen()));
  }

  Future<_DateFilter?> _abrirDateDialog({
    _DateFilter? initial,
    required String label,
  }) {
    return showDialog<_DateFilter>(
      context: context,
      builder: (_) => _DateFilterDialog(initial: initial, label: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const Text('Modo de consulta SAP',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Escolha como os preços serão buscados.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(child: _modoCard(SapModo.lista, 'Lista', Icons.list_alt)),
              const SizedBox(width: 12),
              Expanded(child: _modoCard(SapModo.grupo, 'Lista + Grupo', Icons.group_work_outlined)),
            ],
          ),

          const SizedBox(height: 20),

          const Text('Lista SAP (pltyp)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _loadingListas
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<PriceList>(
                  value: _listaSelecionada,
                  hint: const Text('Selecione a lista...'),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                  items: _listas
                      .map((l) => DropdownMenuItem(
                          value: l, child: Text(l.description)))
                      .toList(),
                  onChanged: (v) => setState(() => _listaSelecionada = v),
                ),

          if (_modo == SapModo.grupo) ...[
            const SizedBox(height: 16),
            const Text('Grupo SAP (kdgrp)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: 'Ex: 01',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
              ),
              onChanged: (v) => setState(() => _kdgrp = v.trim()),
            ),
          ],

          const SizedBox(height: 16),

          // ── Filtros de data ────────────────────────────────────────
          const Text('Filtros de data',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('datab',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                    const SizedBox(height: 4),
                    _dateFilterButton(
                      filter: _datab,
                      onTap: () async {
                        final r = await _abrirDateDialog(
                            initial: _datab, label: 'Data início (datab)');
                        if (r != null) setState(() => _datab = r);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('datbi',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                    const SizedBox(height: 4),
                    _dateFilterButton(
                      filter: _datbi,
                      placeholder: 'Aberto',
                      onTap: () async {
                        final r = await _abrirDateDialog(
                            initial: _datbi, label: 'Data fim (datbi)');
                        if (r != null) setState(() => _datbi = r);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (_erro != null) ...[
            const SizedBox(height: 12),
            Text(_erro!, style: const TextStyle(color: Colors.red)),
          ],

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _podeConfirmar ? _confirmar : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _laranja,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Buscar preços',
                  style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modoCard(SapModo modo, String label, IconData icon) {
    final selected = _modo == modo;
    return GestureDetector(
      onTap: () => setState(() => _modo = modo),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? _laranja.withOpacity(0.08) : Colors.grey.shade50,
          border: Border.all(
            color: selected ? _laranja : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? _laranja : Colors.grey.shade500, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? _laranja : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateFilterButton({
    _DateFilter? filter,
    String placeholder = '—',
    required VoidCallback onTap,
  }) {
    final hasFilter = filter != null;
    final label = hasFilter
        ? '${filter.op.label}  ${_fmtDisplay(filter.date)}'
        : placeholder;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
        side: BorderSide(
            color: hasFilter ? _laranja : Colors.grey.shade300),
        foregroundColor:
            hasFilter ? _laranja : Colors.grey.shade600,
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 15,
              color: hasFilter ? _laranja : Colors.grey.shade500),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  String _fmtDisplay(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

// ── Dialog customizado ─────────────────────────────────────────────────────

class _DateFilterDialog extends StatefulWidget {
  final _DateFilter? initial;
  final String label;

  const _DateFilterDialog({required this.initial, required this.label});

  @override
  State<_DateFilterDialog> createState() => _DateFilterDialogState();
}

class _DateFilterDialogState extends State<_DateFilterDialog> {
  late DateOp _op;
  late TextEditingController _ctrl;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _op = widget.initial?.op ?? DateOp.gte;
    final d = widget.initial?.date ?? DateTime.now();
    _ctrl = TextEditingController(
      text: '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/'
            '${d.year}',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  DateTime? _parse() {
    // aceita DD/MM/AAAA
    final parts = _ctrl.text.split('/');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    if (y < 1900 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  void _confirmar() {
    final date = _parse();
    if (date == null) {
      setState(() => _erro = 'Data inválida. Use DD/MM/AAAA');
      return;
    }
    Navigator.of(context).pop(_DateFilter(op: _op, date: date));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined,
                    color: _laranja, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.label,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Operador ───────────────────────────────────────────
            Text('Operador',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: DateOp.values.map((op) {
                final sel = op == _op;
                return GestureDetector(
                  onTap: () => setState(() => _op = op),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel
                          ? _laranja
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? _laranja : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          op.label,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: sel ? Colors.white : Colors.grey.shade800,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          op.description,
                          style: TextStyle(
                            fontSize: 11,
                            color: sel
                                ? Colors.white.withOpacity(0.85)
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

            // ── Campo de data ──────────────────────────────────────
            Text('Data',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [_DateMaskFormatter()],
              style: const TextStyle(fontSize: 16, letterSpacing: 1),
              decoration: InputDecoration(
                hintText: 'DD/MM/AAAA',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.edit_calendar_outlined,
                    size: 18, color: _laranja),
                errorText: _erro,
                errorStyle: const TextStyle(fontSize: 11),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: _laranja, width: 1.8),
                ),
              ),
              onChanged: (_) {
                if (_erro != null) setState(() => _erro = null);
              },
            ),

            const SizedBox(height: 20),

            // ── Ações ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade600,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirmar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _laranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: const Text('Confirmar',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}