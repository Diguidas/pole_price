import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';

const _laranja = Color(0xFFFF6B00);

Future<void> abrirSeletorTargets(
  BuildContext context,
  PrecoController controller,
) async {
  await showDialog(
    context: context,
    builder: (context) => _SeletorTargetsDialog(controller: controller),
  );
}

class _SeletorTargetsDialog extends StatefulWidget {
  final PrecoController controller;
  const _SeletorTargetsDialog({required this.controller});

  @override
  State<_SeletorTargetsDialog> createState() => _SeletorTargetsDialogState();
}

class _SeletorTargetsDialogState extends State<_SeletorTargetsDialog> {
  late List<String> tempTargets;
  String pesquisa = '';

  @override
  void initState() {
    super.initState();
    tempTargets = List.from(widget.controller.targets);
  }

  List get _disponiveis => widget.controller.listas.where((l) {
        final matchFiltro =
            l.description.toLowerCase().contains(pesquisa.toLowerCase()) ||
                l.id.toLowerCase().contains(pesquisa.toLowerCase());
        return l.id != widget.controller.selecionada?.id && matchFiltro;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final disponiveis = _disponiveis;
    final todosSelecionados =
        disponiveis.isNotEmpty && disponiveis.every((l) => tempTargets.contains(l.id));

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 520,
        height: 580,
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
                    child: const Icon(Icons.checklist_rtl_outlined, color: _laranja, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vincular listas destino',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Tabelas filhas que herdarão os valores',
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

            // ── Campo de pesquisa + selecionar todos ─────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Pesquisar tabelas...',
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
                ],
              ),
            ),

            // ── Barra de ações ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Text(
                    '${disponiveis.length} tabela${disponiveis.length != 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      setState(() {
                        if (todosSelecionados) {
                          for (var l in disponiveis) {
                            tempTargets.remove(l.id);
                          }
                        } else {
                          for (var l in disponiveis) {
                            if (!tempTargets.contains(l.id)) tempTargets.add(l.id);
                          }
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            todosSelecionados
                                ? Icons.deselect
                                : Icons.select_all,
                            size: 14,
                            color: _laranja,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            todosSelecionados ? 'Desmarcar todos' : 'Selecionar todos',
                            style: const TextStyle(
                              fontSize: 11,
                              color: _laranja,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFF0F0F0)),

            // ── Lista com checkboxes ──────────────────────────────────
            Expanded(
              child: disponiveis.isEmpty
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
                      itemCount: disponiveis.length,
                      itemBuilder: (context, index) {
                        final lista = disponiveis[index];
                        final marcado = tempTargets.contains(lista.id);

                        return InkWell(
                          onTap: () {
                            setState(() {
                              if (marcado) {
                                tempTargets.remove(lista.id);
                              } else {
                                tempTargets.add(lista.id);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: marcado ? _laranja.withOpacity(0.05) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: marcado
                                    ? _laranja.withOpacity(0.2)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: marcado ? _laranja : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: marcado ? _laranja : const Color(0xFFCCCCCC),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: marcado
                                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                                      : null,
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
                                          fontWeight: marcado ? FontWeight.w500 : FontWeight.w400,
                                          color: marcado ? const Color(0xFF212121) : const Color(0xFF424242),
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
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // ── Footer ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
              ),
              child: Row(
                children: [
                  if (tempTargets.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _laranja.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${tempTargets.length} selecionada${tempTargets.length != 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _laranja,
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF9E9E9E)),
                    child: const Text('Cancelar', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _laranja,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      widget.controller.targets
                        ..clear()
                        ..addAll(tempTargets);
                      widget.controller.notifyListeners();
                      Navigator.pop(context);
                    },
                    child: const Text('Confirmar', style: TextStyle(fontSize: 13)),
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