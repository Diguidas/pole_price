import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/material_preco.dart';

class TabelaPrecos extends StatelessWidget {
  final PrecoController controller;

  const TabelaPrecos({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.selecionada == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_chart_outlined,
                size: 48, color: Colors.grey.shade300),
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
        Expanded(
          child: ListView.builder(
            itemCount: controller.filtrados.length,
            itemBuilder: (context, index) {
              final m = controller.filtrados[index];
              final isLast = index == controller.filtrados.length - 1;
              return _ItemMaterial(
                material: m,
                isLast: isLast,
                onPrecoChanged: (novo) => controller.atualizarPreco(m, novo),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _legenda(List<MaterialPreco> lista) {
    int ok = 0, atencao = 0, critico = 0, semCpv = 0;
    for (final m in lista) {
      switch (m.statusMargem) {
        case 'ok': ok++; break;
        case 'atencao': atencao++; break;
        case 'critico': critico++; break;
        default: semCpv++;
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
          if (ok > 0) _legendaItem(Colors.green, '$ok ok'),
          if (atencao > 0) ...[
            const SizedBox(width: 14),
            _legendaItem(Colors.orange, '$atencao atenção'),
          ],
          if (critico > 0) ...[
            const SizedBox(width: 14),
            _legendaItem(Colors.red, '$critico crítico'),
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
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }
}

// ── Item individual ──────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            // Código
            Expanded(
              flex: 2,
              child: Text(
                m.codigo,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontFamily: 'monospace',
                ),
              ),
            ),

            // Descrição + CPV
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.description,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (m.cpv != null)
                    Text(
                      'CPV R\$ ${m.cpv!.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400),
                    ),
                ],
              ),
            ),

            // Preço atual
            Expanded(
              flex: 2,
              child: Text(
                'R\$ ${m.precoAtual.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade700),
              ),
            ),

            const SizedBox(width: 6),

            // Input novo preço
            Expanded(
              flex: 2,
              child: TextField(
                controller: _ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '0,00',
                  prefixText: 'R\$ ',
                  prefixStyle:
                      TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
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
                        color: Color(0xFFFF6B00), width: 1.5),
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

            // Margem / semáforo
            Expanded(
              flex: 2,
              child: _semaforo(m),
            ),
          ],
        ),
      ),
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
            Icon(_iconeStatus(status),
                size: 13, color: _corStatus(status)),
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
              color: _corStatus(status).withOpacity(0.8)),
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
      case 'critico':
        return m.margemOferta != null
            ? 'mín ${(m.margemOferta! * 100).toStringAsFixed(0)}%'
            : 'crítico';
      default:
        return m.novoPreco > 0 ? 'variação' : 'sem CPV';
    }
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'ok':      return Colors.green;
      case 'atencao': return Colors.orange;
      case 'critico': return Colors.red;
      default:        return Colors.grey.shade400;
    }
  }

  IconData _iconeStatus(String status) {
    switch (status) {
      case 'ok':      return Icons.check_circle_outline;
      case 'atencao': return Icons.warning_amber_outlined;
      case 'critico': return Icons.cancel_outlined;
      default:        return Icons.help_outline;
    }
  }
}