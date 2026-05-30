import 'package:flutter/material.dart';
import 'package:pole_price/models/material_preco.dart';
import 'package:pole_price/models/pricelist_model.dart';
import 'package:pole_price/models/regra_ajuste.dart';

/// Bottom sheet / tela de resumo exibida ao clicar em "Salvar para aprovação".
///
/// Mostra:
///   - Lista mãe (master list)
///   - Listas destino (targets) com suas regras de ajuste
///   - Todos os materiais alterados (preço antigo × novo)
///
/// Uso:
///   final confirm = await showResumoDraft(
///     context: context,
///     listasMae: controller.listas,
///     selecionada: controller.selecionada!,
///     materiais: controller.materiais,
///     targets: controller.targets,
///     regras: controller.regras,
///   );
///   if (confirm == true) await controller.salvar();

Future<bool?> showResumoDraft({
  required BuildContext context,
  required List<PriceList> listasMae,
  required PriceList selecionada,
  required List<MaterialPreco> materiais,
  required List<String> targets,
  required List<RegraAjuste> regras,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ResumoDraftSheet(
      listasMae: listasMae,
      selecionada: selecionada,
      materiais: materiais,
      targets: targets,
      regras: regras,
    ),
  );
}

class _ResumoDraftSheet extends StatelessWidget {
  final List<PriceList> listasMae;
  final PriceList selecionada;
  final List<MaterialPreco> materiais;
  final List<String> targets;
  final List<RegraAjuste> regras;

  const _ResumoDraftSheet({
    required this.listasMae,
    required this.selecionada,
    required this.materiais,
    required this.targets,
    required this.regras,
  });

  static const _laranja = Color(0xFFFF6B00);

  // Materiais que tiveram o preço alterado
  List<MaterialPreco> get _alterados =>
      materiais.where((m) => m.novoPreco > 0 && m.novoPreco != m.precoAtual).toList();

  // Listas destino com nome
  List<PriceList> get _listasDestino =>
      listasMae.where((l) => targets.contains(l.id)).toList();

  @override
  Widget build(BuildContext context) {
    final alterados = _alterados;
    final listasDestino = _listasDestino;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF5F6F8),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // ── Handle ───────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Header ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _laranja.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.summarize_outlined,
                        color: _laranja, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumo do rascunho',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Revise as alterações antes de enviar para aprovação',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),

            // ── Corpo scrollável ─────────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  // Badges de contagem
                  _badgesResumo(alterados.length, listasDestino.length),
                  const SizedBox(height: 16),

                  // Lista mãe
                  _sectionCard(
                    icon: Icons.table_chart_outlined,
                    titulo: 'Lista mãe',
                    child: _chipLista(selecionada.description, isPrimary: true),
                  ),
                  const SizedBox(height: 12),

                  // Listas destino + regras por lista
                  if (listasDestino.isNotEmpty) ...[
                    _sectionCard(
                      icon: Icons.sync_alt,
                      titulo: 'Listas destino',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: listasDestino.map((lista) {
                          final regrasLista = regras
                              .where((r) => r.targetListId == lista.id)
                              .toList();
                          return _listaDestinoItem(lista, regrasLista);
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Materiais alterados
                  _sectionCard(
                    icon: Icons.inventory_2_outlined,
                    titulo: 'Materiais alterados',
                    badge: alterados.length.toString(),
                    child: alterados.isEmpty
                        ? _emptyState('Nenhum preço foi alterado manualmente.')
                        : Column(
                            children: [
                              // Cabeçalho da tabela
                              _tabelaHeader(),
                              const Divider(height: 1),
                              ...alterados.map((m) => _materialRow(m)),
                            ],
                          ),
                  ),
                  const SizedBox(height: 80), // espaço para os botões
                ],
              ),
            ),

            // ── Rodapé com botões ────────────────────────────────────
            _rodape(context, alterados),
          ],
        ),
      ),
    );
  }

  Widget _badgesResumo(int qtdMateriais, int qtdListas) {
    return Row(
      children: [
        Expanded(
          child: _badgeCard(
            valor: qtdMateriais.toString(),
            label: 'Materiais\nalterados',
            icon: Icons.edit_outlined,
            cor: _laranja,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _badgeCard(
            valor: qtdListas.toString(),
            label: 'Listas\ndestino',
            icon: Icons.format_list_bulleted,
            cor: Colors.blue.shade600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _badgeCard(
            valor: regras.length.toString(),
            label: 'Exceções\nconfigur.',
            icon: Icons.rule_outlined,
            cor: Colors.purple.shade600,
          ),
        ),
      ],
    );
  }

  Widget _badgeCard({
    required String valor,
    required String label,
    required IconData icon,
    required Color cor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: cor, size: 16),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(valor,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cor)),
              Text(label,
                  style:
                      const TextStyle(fontSize: 10, color: Colors.grey),
                  maxLines: 2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String titulo,
    String? badge,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  titulo,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _laranja.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _laranja),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _chipLista(String nome, {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isPrimary
            ? _laranja.withOpacity(0.08)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPrimary ? _laranja.withOpacity(0.3) : Colors.grey.shade300,
        ),
      ),
      child: Text(
        nome,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isPrimary ? _laranja : Colors.black87,
        ),
      ),
    );
  }

  Widget _listaDestinoItem(PriceList lista, List<RegraAjuste> regrasLista) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chipLista(lista.description),
          if (regrasLista.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...regrasLista.map((r) => _regraChip(r)),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                'Sem exceções — herda os preços da lista mãe',
                style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
  }

  Widget _regraChip(RegraAjuste r) {
    final sinal = r.valor >= 0 ? '+' : '';
    final sufixo = r.tipo == 'Percentual' ? '%' : ' R\$';
    final nivelLabel = r.nivel == 'Tabela'
        ? 'Tabela inteira'
        : r.nivel == 'Grupo'
            ? 'Grupo: ${r.clusterNome ?? r.clusterId ?? ''}'
            : 'Material: ${r.materialNome ?? r.materialId ?? ''}';

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 8),
      child: Row(
        children: [
          Icon(Icons.subdirectory_arrow_right,
              size: 14, color: Colors.grey.shade400),
          const SizedBox(width: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.purple.shade100),
            ),
            child: Text(
              '$nivelLabel  ·  $sinal${r.valor}$sufixo',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.purple.shade700,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabelaHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(
            flex: 4,
            child: Text('Material',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text('Preço anterior',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade500)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text('Novo preço',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade500)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text('Δ',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade500)),
          ),
        ],
      ),
    );
  }

  Widget _materialRow(MaterialPreco m) {
    final delta = m.precoAtual > 0
        ? ((m.novoPreco - m.precoAtual) / m.precoAtual) * 100
        : 0.0;
    final subiu = m.novoPreco > m.precoAtual;
    final deltaColor = subiu ? Colors.green.shade700 : Colors.red.shade600;
    final deltaIcon =
        subiu ? Icons.arrow_upward : Icons.arrow_downward;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade100),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.description,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  m.codigo,
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              _fmt(m.precoAtual),
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  decoration: TextDecoration.lineThrough),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              _fmt(m.novoPreco),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(deltaIcon, size: 11, color: deltaColor),
                const SizedBox(width: 2),
                Text(
                  '${delta.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: deltaColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Text(msg,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _rodape(BuildContext context, List<MaterialPreco> alterados) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.black54)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Confirmar e enviar'),
              onPressed: alterados.isEmpty && targets.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _laranja,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}