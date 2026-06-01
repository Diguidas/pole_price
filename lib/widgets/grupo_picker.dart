// lib/widgets/grupo_picker.dart
//
// Widget reutilizável para seleção de grupo de clientes (kdgrp).
// Espelho do ListaPicker — mesma UX, dados de price_groups.
// Uso:
//   final grupo = await showGrupoPicker(context);
//   // ou embutido:
//   GrupoPicker(onSelected: (ref) { ... })

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modelo
// ─────────────────────────────────────────────────────────────────────────────

class GrupoRef {
  final String kdgrp;
  final String ktext;
  const GrupoRef({required this.kdgrp, required this.ktext});

  bool matches(String q) {
    final lower = q.toLowerCase();
    return kdgrp.toLowerCase().contains(lower) ||
        ktext.toLowerCase().contains(lower);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Função helper — abre o dialog e retorna o item selecionado
// ─────────────────────────────────────────────────────────────────────────────

Future<GrupoRef?> showGrupoPicker(BuildContext context) {
  return showDialog<GrupoRef>(
    context: context,
    builder: (_) => const _GrupoPickerDialog(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _GrupoPickerDialog extends StatelessWidget {
  const _GrupoPickerDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: GrupoPicker(
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

class GrupoPicker extends StatefulWidget {
  final void Function(GrupoRef) onSelected;
  final VoidCallback? onCancel;
  final bool showCancelButton;

  /// Se fornecido, usa essa lista em vez de buscar do Supabase.
  final List<GrupoRef>? grupos;

  const GrupoPicker({
    super.key,
    required this.onSelected,
    this.onCancel,
    this.showCancelButton = false,
    this.grupos,
  });

  @override
  State<GrupoPicker> createState() => _GrupoPickerState();
}

class _GrupoPickerState extends State<GrupoPicker> {
  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _bgSuave = Color(0xFFF8FAFC);
  static const _verde = Color(0xFF0EA5E9); // azul para diferenciar do laranja

  bool _loading = false;
  List<GrupoRef> _todos = [];
  String _busca = '';
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();

  List<GrupoRef> get _filtrados {
    if (_busca.trim().isEmpty) return _todos;
    return _todos.where((g) => g.matches(_busca)).toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.grupos != null) {
      _todos = widget.grupos!;
    } else {
      _carregar();
    }
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
          .from('price_groups')
          .select('kdgrp, ktext')
          .order('ktext');
      if (!mounted) return;
      setState(() {
        _todos = (res as List)
            .map((r) => GrupoRef(
                  kdgrp: r['kdgrp']?.toString() ?? '',
                  ktext: r['ktext']?.toString() ?? '',
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
    final filtrados = _filtrados;

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
                  color: _verde.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_tree_rounded,
                    color: _verde, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selecionar Grupo de Clientes',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _slate900,
                          letterSpacing: -0.3),
                    ),
                    Text(
                      'Busque pelo código ou nome do grupo',
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
              hintText: 'Buscar grupo…',
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
                      const BorderSide(color: _verde, width: 1.8)),
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
                : '${filtrados.length} grupo${filtrados.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 11, color: _slate600),
          ),
        ),

        const SizedBox(height: 6),
        const Divider(height: 1, color: _slate200),

        // ── Lista ────────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: _verde))
              : filtrados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 36, color: Colors.grey.shade300),
                          const SizedBox(height: 10),
                          Text(
                            'Nenhum grupo encontrado',
                            style: TextStyle(
                                color: Colors.grey.shade400,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: filtrados.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: _slate200),
                      itemBuilder: (context, i) {
                        final g = filtrados[i];
                        return InkWell(
                          onTap: () => widget.onSelected(g),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: _verde.withOpacity(0.07),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    g.kdgrp,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: _verde,
                                        fontFamily: 'monospace'),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    g.ktext,
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