import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';

const _laranja = Color(0xFFFF6B00);

Future<void> abrirSeletorListaMae(
  BuildContext context,
  PrecoController controller,
) async {
  await showDialog(
    context: context,
    builder: (context) => _SeletorListaMaeDialog(controller: controller),
  );
}

class _SeletorListaMaeDialog extends StatefulWidget {
  final PrecoController controller;
  const _SeletorListaMaeDialog({required this.controller});

  @override
  State<_SeletorListaMaeDialog> createState() => _SeletorListaMaeDialogState();
}

class _SeletorListaMaeDialogState extends State<_SeletorListaMaeDialog> {
  String pesquisa = '';
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtradas = widget.controller.listas.where((l) {
      return l.description.toLowerCase().contains(pesquisa.toLowerCase()) ||
          l.id.toLowerCase().contains(pesquisa.toLowerCase());
    }).toList();

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFf0f0f0))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _laranja.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.table_chart_outlined, color: _laranja, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selecionar tabela de preço',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Lista mãe — base de edição',
                        style: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFF9E9E9E)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Campo de pesquisa ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Pesquisar por nome ou ID...',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFBDBDBD)),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9E9E9E)),
                  filled: true,
                  fillColor: const Color(0xFFF8F8F8),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _laranja, width: 1.5),
                  ),
                ),
                onChanged: (val) => setState(() => pesquisa = val),
              ),
            ),

            // ── Contador ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                '${filtradas.length} tabela${filtradas.length != 1 ? 's' : ''} encontrada${filtradas.length != 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
              ),
            ),

            // ── Lista ────────────────────────────────────────────────
            Expanded(
              child: filtradas.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 32, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text(
                            'Nenhuma tabela encontrada',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      itemCount: filtradas.length,
                      itemBuilder: (context, index) {
                        final lista = filtradas[index];
                        final isSelected = widget.controller.selecionada?.id == lista.id;

                        return InkWell(
                          onTap: () {
                            widget.controller.selecionarLista(lista);
                            Navigator.pop(context);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? _laranja.withOpacity(0.06) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? _laranja.withOpacity(0.25) : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? _laranja.withOpacity(0.12)
                                        : const Color(0xFFF5F5F5),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    Icons.table_chart_outlined,
                                    size: 16,
                                    color: isSelected ? _laranja : const Color(0xFFBDBDBD),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lista.description,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                          color: isSelected ? _laranja : const Color(0xFF212121),
                                        ),
                                      ),
                                      Text(
                                        'ID: ${lista.id}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF9E9E9E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle, size: 16, color: _laranja),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}