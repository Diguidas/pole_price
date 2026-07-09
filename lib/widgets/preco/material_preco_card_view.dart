// Card somente-leitura do motor de preço (Atual/Novo/Oferta), usado na
// tela de Histórico para exibir como um material ficou num draft aprovado.
// Mesma estrutura visual da tela de Gestão de Preços, sem campos editáveis.
import 'package:flutter/material.dart';
import 'package:pole_price/models/material_preco.dart';

const _corAtualBg = Color(0xFFF0F6FF);
const _corAtualBorda = Color(0xFFBFD7FF);
const _corAtualLabel = Color(0xFF3B82F6);

const _corNovoBg = Color(0xFFFFF8F2);
const _corNovoBorda = Color(0xFFFFCCA0);
const _corNovoLabel = Color(0xFFFF6B00);

const _corOfertaBg = Color(0xFFF0FDF6);
const _corOfertaBorda = Color(0xFF86EFAC);
const _corOfertaLabel = Color(0xFF16A34A);

const _labelFontSize = 10.0;
const _valorFontSize = 13.0;

class MaterialPrecoCardView extends StatelessWidget {
  final MaterialPreco m;

  const MaterialPrecoCardView({super.key, required this.m});

  Color _corStatus(String status) {
    switch (status) {
      case 'ok':
        return Colors.green;
      case 'atencao':
        return Colors.orange;
      case 'critico':
        return Colors.deepOrange;
      case 'sem margem':
        return Colors.red;
      case 'prejuizo':
        return Colors.red.shade900;
      default:
        return Colors.grey.shade300;
    }
  }

  @override
  Widget build(BuildContext context) {
    final corLinha = _corStatus(m.statusMargem);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: corLinha),
              Expanded(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  m.codigo,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade400,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  m.description.isNotEmpty
                                      ? m.description
                                      : m.codigo,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                          if (m.cpv != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 12, top: 2),
                              child: Text(
                                'CPV R\$ ${m.cpv!.toStringAsFixed(2)}  ·  fator ${m.fatorConversao?.toStringAsFixed(1) ?? "—"}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: _secaoAtual()),
                          const SizedBox(width: 10),
                          Expanded(flex: 7, child: _secaoNovo()),
                          const SizedBox(width: 10),
                          Expanded(flex: 3, child: _secaoOferta()),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _secaoAtual() {
    return _secaoBox(
      bg: _corAtualBg,
      borda: _corAtualBorda,
      titulo: 'ATUAL',
      labelColor: _corAtualLabel,
      children: [
        _col('PPV CX', 'R\$ ${m.precoAtual.toStringAsFixed(2)}'),
        _col(
          'PPV Unit',
          m.ppvUnitAtual != null
              ? 'R\$ ${m.ppvUnitAtual!.toStringAsFixed(2)}'
              : '—',
        ),
        _col(
          'PPC',
          m.ppcAtual != null ? 'R\$ ${m.ppcAtual!.toStringAsFixed(2)}' : '—',
          color: Colors.grey.shade400,
        ),
        _col(
          'MC% Cliente',
          m.margemClienteAtual != null
              ? '${(m.margemClienteAtual! * 100).toStringAsFixed(1)}%'
              : '—',
          color: Colors.grey.shade500,
        ),
        _col(
          'MC R\$',
          m.mcReaisAtual != null
              ? 'R\$ ${m.mcReaisAtual!.toStringAsFixed(2)}'
              : '—',
          color: Colors.grey.shade500,
        ),
        _col(
          'MC% Pole',
          m.mcPctAtual != null
              ? '${(m.mcPctAtual! * 100).toStringAsFixed(1)}%'
              : '—',
          color: m.mcPctAtual != null
              ? (m.mcPctAtual! < 0 ? Colors.red.shade900 : Colors.green)
              : Colors.grey.shade400,
          bold: m.mcPctAtual != null,
        ),
      ],
    );
  }

  Widget _secaoNovo() {
    final mcPct = m.mcPctNovo;
    return _secaoBox(
      bg: _corNovoBg,
      borda: _corNovoBorda,
      titulo: 'NOVO',
      labelColor: _corNovoLabel,
      children: [
        _col(
          'PPV CX',
          m.ppvCxNovo != null ? 'R\$ ${m.ppvCxNovo!.toStringAsFixed(2)}' : '—',
        ),
        _col(
          'PPV Unit',
          m.ppvUnitNovo != null
              ? 'R\$ ${m.ppvUnitNovo!.toStringAsFixed(2)}'
              : '—',
        ),
        _col(
          'PPC Novo',
          m.ppcNovoEfetivo != null
              ? 'R\$ ${m.ppcNovoEfetivo!.toStringAsFixed(2)}'
              : '—',
          color: _corNovoLabel,
          bold: true,
        ),
        _col(
          'MC% Cliente',
          m.margemClienteNovo != null
              ? '${(m.margemClienteNovo! * 100).toStringAsFixed(1)}%'
              : '—',
          color: Colors.grey.shade500,
        ),
        _col(
          'MC R\$',
          m.mcReaisNovo != null
              ? 'R\$ ${m.mcReaisNovo!.toStringAsFixed(2)}'
              : '—',
          color: Colors.grey.shade500,
        ),
        _col(
          'MC% Pole',
          mcPct != null ? '${(mcPct * 100).toStringAsFixed(1)}%' : '—',
          color: mcPct != null
              ? _corStatus(m.statusMargem)
              : Colors.grey.shade400,
          bold: mcPct != null,
        ),
        _col(
          '% Reajuste',
          m.reajustePct != null
              ? '${(m.reajustePct! * 100).toStringAsFixed(2)}%'
              : '—',
          color: m.reajustePct != null
              ? (m.reajustePct! > 0
                    ? Colors.green.shade700
                    : m.reajustePct! < 0
                    ? Colors.red
                    : Colors.grey.shade600)
              : Colors.grey.shade400,
        ),
      ],
    );
  }

  Widget _secaoOferta() {
    final ppvUnitOferta = m.ppvUnitOferta;
    final reajOferta =
        (ppvUnitOferta != null && m.ppvUnitAtual != null && m.ppvUnitAtual! > 0)
        ? (ppvUnitOferta / m.ppvUnitAtual!) - 1
        : null;

    return _secaoBox(
      bg: _corOfertaBg,
      borda: _corOfertaBorda,
      titulo: 'OFERTA',
      labelColor: _corOfertaLabel,
      children: [
        _col(
          '% Reajuste',
          reajOferta != null
              ? '${(reajOferta * 100).toStringAsFixed(1)}%'
              : '—',
          color: reajOferta != null
              ? (reajOferta < 0
                    ? Colors.green.shade700
                    : Colors.orange.shade700)
              : Colors.grey.shade400,
        ),
        _col(
          'PPV Unit',
          ppvUnitOferta != null
              ? 'R\$ ${ppvUnitOferta.toStringAsFixed(2)}'
              : '—',
          color: ppvUnitOferta != null
              ? Colors.green.shade700
              : Colors.grey.shade400,
        ),
        _col(
          'PPC',
          m.ppcOfertaOverride != null
              ? 'R\$ ${m.ppcOfertaOverride!.toStringAsFixed(2)}'
              : '—',
        ),
      ],
    );
  }

  Widget _secaoBox({
    required Color bg,
    required Color borda,
    required String titulo,
    required Color labelColor,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: labelColor,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Row(children: children),
        ],
      ),
    );
  }

  Widget _col(String label, String value, {Color? color, bool bold = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: _labelFontSize,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: _valorFontSize,
                  color: color ?? Colors.grey.shade700,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
