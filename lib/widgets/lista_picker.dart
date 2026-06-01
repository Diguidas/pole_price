// lib/widgets/lista_picker.dart
//
// Widget reutilizável para seleção de lista de preço (pltyp).
// Exibe um campo de busca + lista filtrada em tempo real.
// Uso:
//   final pltyp = await showListaPicker(context);
//   // ou embutido:
//   ListaPicker(onSelected: (ref) { ... })

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modelo
// ─────────────────────────────────────────────────────────────────────────────

class ListaRef {
  final String pltyp;
  final String ptext;
  const ListaRef({required this.pltyp, required this.ptext});

  bool matches(String q) {
    final lower = q.toLowerCase();
    return pltyp.toLowerCase().contains(lower) ||
        ptext.toLowerCase().contains(lower);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Função helper — abre o dialog e retorna o item selecionado
// ─────────────────────────────────────────────────────────────────────────────

Future<ListaRef?> showListaPicker(BuildContext context) {
  return showDialog<ListaRef>(
    context: context,
    builder: (_) => const _ListaPickerDialog(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ListaPickerDialog extends StatelessWidget {
  const _ListaPickerDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: ListaPicker(
          onSelected: (ref) => Navigator.of(context).pop(ref),
          onCancel: () => Navigator.of(context).pop(),
          showCancelButton: true,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget embutível
// ─────────────────────────────────────────────────────────────────────────────

class ListaPicker extends StatefulWidget {
  final void Function(ListaRef) onSelected;
  final VoidCallback? onCancel;
  final bool showCancelButton;

  /// Se fornecido, usa essa lista em vez de buscar do Supabase.
  final List<ListaRef>? listas;

  const ListaPicker({
    super.key,
    required this.onSelected,
    this.onCancel,
    this.showCancelButton = false,
    this.listas,
  });

  @override
  State<ListaPicker> createState() => _ListaPickerState();
}

class _ListaPickerState extends State<ListaPicker> {
  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _bgSuave = Color(0xFFF8FAFC);

  bool _loading = false;
  List<ListaRef> _todas = [];
  String _busca = '';
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();

  List<ListaRef> get _filtradas {
    if (_busca.trim().isEmpty) return _todas;
    return _todas.where((l) => l.matches(_busca)).toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.listas != null) {
      _todas = widget.listas!;
    } else {
      _carregar();
    }
    // Auto-foca no campo de busca
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .from('price_lists')
          .select('pltyp, ptext')
          .order('ptext');
      if (!mounted) return;
      setState(() {
        _todas = (res as List)
            .map((r) => ListaRef(
                  pltyp: r['pltyp']?.toString() ?? '',
                  ptext: r['ptext']?.toString() ?? '',
                ))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtradas = _filtradas;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _laranja.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.list_alt_rounded,
                    color: _laranja, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selecionar Lista de Preço',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _slate900,
                          letterSpacing: -0.3),
                    ),
                    Text(
                      'Busque pelo código ou nome da lista',
                      style: TextStyle(fontSize: 11, color: _slate600),
                    ),
                  ],
                ),
              ),
              if (widget.showCancelButton)
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: _slate600),
                  onPressed: widget.onCancel,
                  style: IconButton.styleFrom(
                      hoverColor: const Color(0xFFF1F5F9)),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Campo de busca ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchCtrl,
            focusNode: _focusNode,
            onChanged: (v) => setState(() => _busca = v),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Buscar lista…',
              hintStyle: const TextStyle(color: _slate600, fontSize: 13),
              prefixIcon:
                  const Icon(Icons.search_rounded, size: 18, color: _slate600),
              suffixIcon: _busca.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded,
                          size: 16, color: _slate600),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _busca = '');
                      },
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: _bgSuave,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _slate200)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: _laranja, width: 1.8)),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // ── Contador ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _loading
                ? 'Carregando…'
                : '${filtradas.length} lista${filtradas.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 11, color: _slate600),
          ),
        ),

        const SizedBox(height: 6),
        const Divider(height: 1, color: _slate200),

        // ── Lista ────────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: _laranja))
              : filtradas.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 36, color: Colors.grey.shade300),
                          const SizedBox(height: 10),
                          Text(
                            'Nenhuma lista encontrada',
                            style: TextStyle(
                                color: Colors.grey.shade400,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: filtradas.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: _slate200),
                      itemBuilder: (context, i) {
                        final l = filtradas[i];
                        return InkWell(
                          onTap: () => widget.onSelected(l),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: _laranja.withOpacity(0.07),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    l.pltyp,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: _laranja,
                                        fontFamily: 'monospace'),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    l.ptext,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _slate900),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded,
                                    size: 18, color: _slate600),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}