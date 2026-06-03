import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/material_preco.dart';

class TabelaPrecos extends StatefulWidget {
  final PrecoController controller;

  const TabelaPrecos({
    super.key,
    required this.controller,
  });

  @override
  State<TabelaPrecos> createState() => _TabelaPrecosState();
}

class _TabelaPrecosState extends State<TabelaPrecos> {
  // ScrollController local — vive junto com este widget, não no singleton.
  // Evita offsets obsoletos entre sessões e acúmulo de listeners.
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  PrecoController get ctrl => widget.controller;

  @override
  Widget build(BuildContext context) {
    if (ctrl.pltyp == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_chart_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Selecione uma tabela para ver os materiais',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    if (ctrl.filtrados.isEmpty) {
      return Center(
        child: Text(
          'Nenhum material encontrado',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return Column(
      children: [
        RepaintBoundary(child: _legenda(ctrl.filtrados)),
        _cabecalho(),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            itemCount: ctrl.filtrados.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: false,
            itemBuilder: (context, index) {
              final m = ctrl.filtrados[index];
              return _ItemMaterial(
                key: ValueKey(m.codigo),
                material: m,
                isLast: index == ctrl.filtrados.length - 1,
                onPrecoChanged: (novo) => ctrl.atualizarPreco(m, novo),
                onPrecoConfirmado: (novo) =>
                    ctrl.atualizarPreco(m, novo, promover: true),
                onRemover: () => ctrl.removerMaterial(m),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cabecalho() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // Borda status (3px) — espaçador
          const SizedBox(width: 3),
          const SizedBox(width: 8),
          _cabTxt('Código / Descrição', flex: 5),
          _cabTxt('Vigência', flex: 3, align: TextAlign.center),
          _cabTxt('Preço SAP', flex: 2, align: TextAlign.right),
          _cabTxt('kg sug', flex: 2, align: TextAlign.right),
          const SizedBox(width: 6),
          _cabTxt('Novo Preço', flex: 2, align: TextAlign.right),
          const SizedBox(width: 6),
          _cabTxt('Margem', flex: 2, align: TextAlign.right),
          const SizedBox(width: 32), // botão remover
        ],
      ),
    );
  }

  Widget _cabTxt(
    String label, {
    int flex = 1,
    TextAlign align = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _legenda(List<MaterialPreco> lista) {
    int ok = 0,
        atencao = 0,
        semMargem = 0,
        semCpv = 0,
        bloqueados = 0,
        inativos = 0;
    for (final m in lista) {
      if (m.bloqueado) bloqueados++;
      if (m.inativo) inativos++;
      switch (m.statusMargem) {
        case 'ok':
          ok++;
          break;
        case 'atencao':
          atencao++;
          break;
        case 'sem margem':
          semMargem++;
          break;
        default:
          semCpv++;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text(
            '${lista.length} materiais',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 16),
          if (ok > 0) _legendaItem(Colors.green, '$ok ok'),
          if (atencao > 0) ...[
            const SizedBox(width: 14),
            _legendaItem(Colors.orange, '$atencao atenção'),
          ],
          if (semMargem > 0) ...[
            const SizedBox(width: 14),
            _legendaItem(Colors.red, '$semMargem sem margem'),
          ],
          if (semCpv > 0) ...[
            const SizedBox(width: 14),
            _legendaItem(Colors.grey, '$semCpv sem CPV'),
          ],
          if (bloqueados > 0) ...[
            const SizedBox(width: 14),
            _legendaItem(
              Colors.red.shade400,
              '$bloqueados bloqueado',
              icon: Icons.lock_outline,
            ),
          ],
          if (inativos > 0) ...[
            const SizedBox(width: 14),
            _legendaItem(
              Colors.orange.shade700,
              '$inativos inativo',
              icon: Icons.pause_circle_outline,
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendaItem(Color cor, String label, {IconData? icon}) {
    return Row(
      children: [
        icon != null
            ? Icon(icon, size: 8, color: cor)
            : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
              ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

// ── Item individual ──────────────────────────────────────────────────────────

class _ItemMaterial extends StatefulWidget {
  final MaterialPreco material;
  final ValueChanged<double> onPrecoChanged;
  final ValueChanged<double> onPrecoConfirmado;
  final VoidCallback onRemover;
  final bool isLast;

  const _ItemMaterial({
    super.key,
    required this.material,
    required this.onPrecoChanged,
    required this.onPrecoConfirmado,
    required this.onRemover,
    this.isLast = false,
  });

  @override
  State<_ItemMaterial> createState() => _ItemMaterialState();
}

class _ItemMaterialState extends State<_ItemMaterial> {
  late final TextEditingController _precoCtrl;
  late final FocusNode _precoFocus;

  @override
  void initState() {
    super.initState();
    final m = widget.material;
    _precoCtrl = TextEditingController(
      text: m.novoPreco > 0 ? m.novoPreco.toStringAsFixed(2) : '',
    );
    _precoFocus = FocusNode()
      ..addListener(() {
        if (!_precoFocus.hasFocus) {
          // Propaga ao perder foco (usuário rola a lista, toca em outro campo etc.)
          final val =
              double.tryParse(_precoCtrl.text.replaceAll(',', '.')) ?? 0;
          widget.onPrecoChanged(val);
        }
      });
  }

  @override
  void dispose() {
    _precoCtrl.dispose();
    _precoFocus.dispose();
    super.dispose();
  }

  bool get _temRestricao =>
      widget.material.bloqueado || widget.material.inativo;

  Color get _corBordaEsquerda {
    if (_temRestricao) return Colors.red.shade400;
    return _corStatus(widget.material.statusMargem);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    final status = m.statusMargem;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: widget.isLast ? Colors.transparent : Colors.grey.shade100,
          ),
          left: BorderSide(color: _corBordaEsquerda, width: 3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(width: 8),

            // ── Código + Descrição (2 linhas compactas) ──────────────
            Expanded(
              flex: 5,
              child: Tooltip(
                richMessage: _tooltipContent(m),
                preferBelow: true,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          m.codigo,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (_temRestricao) ...[
                          const SizedBox(width: 6),
                          _chipRestricao(m),
                        ],
                      ],
                    ),
                    Text(
                      m.description,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (m.cpv != null)
                      Text(
                        'CPV R\$ ${m.cpv!.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Vigência (só leitura — vem do SAP) ───────────────────
            Expanded(
              flex: 3,
              child: Text(
                m.vigenciaFormatada,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ),

            // ── Preço atual (SAP) ─────────────────────────────────────
            Expanded(
              flex: 2,
              child: Text(
                'R\$ ${m.precoAtual.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),

            const SizedBox(width: 6),

            // ── kg_sug ───────────────────────────────────────────────
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.kgSug != null
                        ? 'R\$ ${m.kgSug!.toStringAsFixed(2)}'
                        : '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: m.kgSug != null
                          ? const Color(0xFF0EA5E9)
                          : Colors.grey.shade400,
                      fontWeight: m.kgSug != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  if (m.margemSugerida != null)
                    Text(
                      '${(m.margemSugerida! * 100).toStringAsFixed(1)}% sug',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade400,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 6),

            // ── Input novo preço ──────────────────────────────────────
            Expanded(
              flex: 2,
              child: TextField(
                controller: _precoCtrl,
                focusNode: _precoFocus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: '0,00',
                  prefixText: 'R\$ ',
                  prefixStyle: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFFF8F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                      color: Color(0xFFFF6B00),
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (v) {
                  // Apenas atualiza a UI localmente — NÃO chama notifyListeners a cada tecla
                  setState(() {});
                },
                onSubmitted: (v) {
                  final val = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                  widget.onPrecoConfirmado(val);
                  FocusScope.of(context).unfocus();
                },
              ),
            ),

            const SizedBox(width: 6),

            // ── Margem / semáforo ─────────────────────────────────────
            Expanded(flex: 2, child: _semaforo(m)),

            // ── Botão remover ─────────────────────────────────────────
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 16,
                color: Colors.grey.shade400,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Remover material',
              onPressed: widget.onRemover,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipRestricao(MaterialPreco m) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (m.bloqueado)
          _chip(
            'BLOQUEADO',
            Colors.red.shade700,
            Colors.red.shade50,
            Colors.red.shade200,
          ),
        if (m.bloqueado && m.inativo) const SizedBox(width: 4),
        if (m.inativo)
          _chip(
            'INATIVO',
            Colors.orange.shade800,
            Colors.orange.shade50,
            Colors.orange.shade200,
          ),
      ],
    );
  }

  Widget _chip(
    String label,
    Color textColor,
    Color bgColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  InlineSpan _tooltipContent(MaterialPreco m) {
    final lines = <String>[];
    lines.add('Código: ${m.codigo}');
    if (m.clusterId != null) lines.add('Cluster: ${m.clusterId}');
    if (m.cpv != null) lines.add('CPV: R\$ ${m.cpv!.toStringAsFixed(4)}');
    if (m.kgSug != null)
      lines.add('kg_sug SAP: R\$ ${m.kgSug!.toStringAsFixed(4)}');
    if (m.margemFlat != null)
      lines.add(
        'Margem mín. (flat): ${(m.margemFlat! * 100).toStringAsFixed(1)}%',
      );
    if (m.margemOferta != null)
      lines.add(
        'Margem mín. (oferta): ${(m.margemOferta! * 100).toStringAsFixed(1)}%',
      );
    lines.add('Vigência: ${m.vigenciaFormatada}');
    if (m.bloqueado) lines.add('⚠ Material bloqueado (LOEVM_KO)');
    if (m.inativo) lines.add('⚠ Material inativo (KZNEP)');
    return TextSpan(
      text: lines.join('\n'),
      style: const TextStyle(fontSize: 11, color: Colors.white, height: 1.6),
    );
  }

  Widget _semaforo(MaterialPreco m) {
    final margem = m.margemSugerida ?? m.margemReal;
    final status = m.statusMargem;
    final temNovoPreco = m.novoPreco > 0;
    final variacaoPct = temNovoPreco && m.precoAtual > 0
        ? ((m.novoPreco - m.precoAtual) / m.precoAtual) * 100
        : null;
    final textoMargem = margem != null
        ? '${(margem * 100).toStringAsFixed(1)}%'
        : variacaoPct != null
        ? '${variacaoPct >= 0 ? '+' : ''}${variacaoPct.toStringAsFixed(1)}%'
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(_iconeStatus(status), size: 13, color: _corStatus(status)),
            const SizedBox(width: 3),
            Text(
              textoMargem,
              style: TextStyle(
                color: _corStatus(status),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
        Text(
          _labelStatus(status, m),
          style: TextStyle(
            fontSize: 9,
            color: _corStatus(status).withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  String _labelStatus(String status, MaterialPreco m) {
    switch (status) {
      case 'ok':
        return 'margem ok';
      case 'atencao':
        return m.margemFlat != null
            ? 'mín ${(m.margemFlat! * 100).toStringAsFixed(0)}%'
            : 'atenção';
      case 'sem margem':
        return m.margemOferta != null
            ? 'mín ${(m.margemOferta! * 100).toStringAsFixed(0)}%'
            : 'sem margem';
      default:
        return m.novoPreco > 0 ? 'variação' : 'sem CPV';
    }
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'ok':
        return Colors.green;
      case 'atencao':
        return Colors.orange;
      case 'sem margem':
        return Colors.red;
      default:
        return Colors.grey.shade400;
    }
  }

  IconData _iconeStatus(String status) {
    switch (status) {
      case 'ok':
        return Icons.check_circle_outline;
      case 'atencao':
        return Icons.warning_amber_outlined;
      case 'sem margem':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }
}

class FontFeature {
  const FontFeature.tabularFigures();
}