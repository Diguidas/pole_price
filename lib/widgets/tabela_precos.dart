import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/material_preco.dart';

class TabelaPrecos extends StatelessWidget {
  final PrecoController controller;

  const TabelaPrecos({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.pltyp == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.table_chart_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'Selecione uma tabela para ver os materiais',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    if (controller.filtrados.isEmpty) {
      return Center(
        child: Text(
          'Nenhum material encontrado',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return Column(
      children: [
        _legenda(controller.filtrados),
        _cabecalho(),
        Expanded(
          child: ListView.builder(
            itemCount: controller.filtrados.length,
            itemBuilder: (context, index) {
              final m = controller.filtrados[index];
              return _ItemMaterial(
                material: m,
                isLast: index == controller.filtrados.length - 1,
                onPrecoChanged: (novo) => controller.atualizarPreco(m, novo),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cabecalho() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          _cabTxt('Código', flex: 2),
          _cabTxt('Descrição / CPV', flex: 4),
          _cabTxt('Vigência', flex: 3, align: TextAlign.center),
          _cabTxt('Preço SAP', flex: 2, align: TextAlign.right),
          _cabTxt('kg sug', flex: 2, align: TextAlign.right),
          const SizedBox(width: 6),
          _cabTxt('Novo Preço', flex: 2, align: TextAlign.right),
          const SizedBox(width: 6),
          _cabTxt('Margem', flex: 2, align: TextAlign.right),
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
    int ok = 0, atencao = 0, semMargem = 0, semCpv = 0;
    for (final m in lista) {
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
        ],
      ),
    );
  }

  Widget _legendaItem(Color cor, String label) {
    return Row(
      children: [
        Container(
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
  final bool isLast;

  const _ItemMaterial({
    required this.material,
    required this.onPrecoChanged,
    this.isLast = false,
  });

  @override
  State<_ItemMaterial> createState() => _ItemMaterialState();
}

class _ItemMaterialState extends State<_ItemMaterial> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.material.novoPreco > 0
          ? widget.material.novoPreco.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
          left: BorderSide(color: _corStatus(status), width: 3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // ── Código ──────────────────────────────────────────────
            Expanded(
              flex: 2,
              child: Text(
                m.codigo,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontFamily: 'monospace',
                ),
              ),
            ),

            // ── Descrição + CPV ──────────────────────────────────────
            Expanded(
              flex: 4,
              child: Tooltip(
                richMessage: _tooltipContent(m),
                preferBelow: true,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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

            // ── Vigência ─────────────────────────────────────────────
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
                controller: _ctrl,
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
                  final val = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                  widget.onPrecoChanged(val);
                  setState(() {});
                },
              ),
            ),

            const SizedBox(width: 6),

            // ── Margem / semáforo ─────────────────────────────────────
            Expanded(flex: 2, child: _semaforo(m)),
          ],
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
    if (m.margemFlat != null) {
      lines.add(
        'Margem mín. (flat): ${(m.margemFlat! * 100).toStringAsFixed(1)}%',
      );
    }
    if (m.margemOferta != null) {
      lines.add(
        'Margem mín. (oferta): ${(m.margemOferta! * 100).toStringAsFixed(1)}%',
      );
    }
    lines.add('Vigência: ${m.vigenciaFormatada}');

    return TextSpan(
      text: lines.join('\n'),
      style: const TextStyle(fontSize: 11, color: Colors.white, height: 1.6),
    );
  }

  Widget _semaforo(MaterialPreco m) {
    final margem = m.margemReal;
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

// ── FontFeature helper (evita import desnecessário) ──────────────────────────
class FontFeature {
  const FontFeature.tabularFigures();
}
