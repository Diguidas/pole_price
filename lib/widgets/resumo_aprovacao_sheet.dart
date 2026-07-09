import 'package:flutter/material.dart';
import 'package:pole_price/models/material_preco.dart';
import 'package:pole_price/models/pricelist_model.dart';
import 'package:pole_price/models/regra_ajuste.dart';

/// Resultado do bottom sheet de resumo.
/// [justificativa] é obrigatória; [sapStatus] é o status SAP escolhido pelo usuário.
class ResumoDraftResult {
  final String justificativa;
  final String sapStatus; // '' = normal, 'L' = bloqueado p/ liberação, 'X' = deletado

  const ResumoDraftResult({
    required this.justificativa,
    required this.sapStatus,
  });
}

/// Bottom sheet / tela de resumo exibida ao clicar em "Salvar para aprovação".
///
/// Mostra:
///   - Lista mãe (master list)
///   - Listas destino (targets) com suas regras de ajuste
///   - Todos os materiais alterados (preço antigo × novo)
///   - Seletor de status SAP (normal / bloqueado p/ liberação / deletado)
///   - Campo obrigatório de justificativa
///
/// Uso:
///   final result = await showResumoDraft(...);
///   if (result != null) await controller.salvar(justificativa: result.justificativa, sapStatus: result.sapStatus);

Future<ResumoDraftResult?> showResumoDraft({
  required BuildContext context,
  required List<PriceList> listasMae,
  required PriceList selecionada,
  required List<MaterialPreco> materiais,
  required List<String> targets,
  required List<RegraAjuste> regras,
}) {
  return showModalBottomSheet<ResumoDraftResult>(
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

class _ResumoDraftSheet extends StatefulWidget {
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

  @override
  State<_ResumoDraftSheet> createState() => _ResumoDraftSheetState();
}

class _ResumoDraftSheetState extends State<_ResumoDraftSheet> {
  static const _laranja = Color(0xFFFF6B00);

  late final TextEditingController _justificativaCtrl;
  bool _justificativaVazia = false;

  // '' = normal/ativo, 'L' = bloqueado p/ liberação, 'X' = deletado
  String _sapStatus = '';

  @override
  void initState() {
    super.initState();
    _justificativaCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _justificativaCtrl.dispose();
    super.dispose();
  }

  List<MaterialPreco> get _alterados => widget.materiais
      .where((m) => m.novoPreco > 0 && m.novoPreco != m.precoAtual)
      .toList();

  List<PriceList> get _listasDestino =>
      widget.listasMae.where((l) => widget.targets.contains(l.id)).toList();

  @override
  Widget build(BuildContext context) {
    final alterados = _alterados;
    final listasDestino = _listasDestino;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
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
                    onPressed: () => Navigator.pop(context),
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
                    child: _chipLista(widget.selecionada.description, isPrimary: true),
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
                          final regrasLista = widget.regras
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
                              _tabelaHeader(),
                              const Divider(height: 1),
                              ...alterados.map((m) => _materialRow(m)),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),

                  // ── Status SAP ────────────────────────────────────
                  _sectionCard(
                    icon: Icons.flag_outlined,
                    titulo: 'Status do preço no SAP *',
                    child: _sapStatusPicker(),
                  ),
                  const SizedBox(height: 12),

                  // ── Justificativa ─────────────────────────────────
                  _sectionCard(
                    icon: Icons.comment_outlined,
                    titulo: 'Justificativa *',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _justificativaCtrl,
                          maxLines: 3,
                          onChanged: (_) {
                            if (_justificativaVazia) {
                              setState(() => _justificativaVazia = false);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Explique o motivo das alterações de preço...',
                            hintStyle: TextStyle(
                                color: Colors.grey.shade400, fontSize: 13),
                            errorText: _justificativaVazia
                                ? 'Justificativa obrigatória para envio.'
                                : null,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: _justificativaVazia
                                    ? Colors.red.shade300
                                    : Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: _laranja, width: 1.5),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  BorderSide(color: Colors.red.shade300),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                  color: Colors.red.shade400, width: 1.5),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 80),
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

  // ── Seletor de status SAP ─────────────────────────────────────────────────

  Widget _sapStatusPicker() {
    final opcoes = [
      _SapStatusOpcao(
        valor: 'L',
        label: 'Ativo / Normal',
        descricao: 'Preço publicado e disponível para uso imediato.',
        icon: Icons.check_circle_outline,
        cor: Colors.green.shade600,
      ),
      _SapStatusOpcao(
        valor: '',
        label: 'Respeitar o atual status no SAP',
        descricao: 'Preço será salvo com o mesmo status que já possui no SAP (bloqueado ou ativo).',
        icon: Icons.lock_outline,
        cor: Colors.orange.shade700,
      ),
      _SapStatusOpcao(
        valor: 'X',
        label: 'Inativo',
        descricao: 'Marca o registro como inativo na lista SAP.',
        icon: Icons.delete_outline,
        cor: Colors.red.shade600,
      ),
    ];

    return Column(
      children: opcoes.map((op) {
        final selecionado = _sapStatus == op.valor;
        return GestureDetector(
          onTap: () => setState(() => _sapStatus = op.valor),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selecionado ? op.cor.withOpacity(0.06) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selecionado ? op.cor : Colors.grey.shade200,
                width: selecionado ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(op.icon, color: selecionado ? op.cor : Colors.grey.shade400, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        op.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selecionado ? op.cor : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        op.descricao,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                if (selecionado)
                  Icon(Icons.radio_button_checked, color: op.cor, size: 18)
                else
                  Icon(Icons.radio_button_unchecked,
                      color: Colors.grey.shade300, size: 18),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Demais widgets internos ───────────────────────────────────────────────

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
            valor: widget.regras.length.toString(),
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
    final ehPolitica = r.clusterNome?.startsWith('[Política] ') ?? false;
    final nivelLabel = r.nivel == 'Tabela'
        ? (ehPolitica ? r.clusterNome! : 'Tabela inteira')
        : r.nivel == 'Grupo'
            ? 'Grupo: ${r.clusterNome ?? r.clusterId ?? ''}'
            : 'Material: ${r.materialNome ?? r.materialId ?? ''}';
    final cor = ehPolitica ? Colors.teal : Colors.purple;

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 8),
      child: Row(
        children: [
          Icon(
            ehPolitica ? Icons.account_tree_outlined : Icons.subdirectory_arrow_right,
            size: 14,
            color: Colors.grey.shade400,
          ),
          const SizedBox(width: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cor.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cor.shade100),
            ),
            child: Text(
              '$nivelLabel  ·  $sinal${r.valor.toStringAsFixed(2)}$sufixo',
              style: TextStyle(
                  fontSize: 11,
                  color: cor.shade700,
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
              onPressed: () => Navigator.pop(context),
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
              onPressed: alterados.isEmpty && widget.targets.isEmpty
                  ? null
                  : () {
                      final justificativa =
                          _justificativaCtrl.text.trim();
                      if (justificativa.isEmpty) {
                        setState(() => _justificativaVazia = true);
                        return;
                      }
                      Navigator.pop(
                        context,
                        ResumoDraftResult(
                          justificativa: justificativa,
                          sapStatus: _sapStatus,
                        ),
                      );
                    },
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

// ── Modelo interno para as opções de status SAP ───────────────────────────────

class _SapStatusOpcao {
  final String valor;
  final String label;
  final String descricao;
  final IconData icon;
  final Color cor;

  const _SapStatusOpcao({
    required this.valor,
    required this.label,
    required this.descricao,
    required this.icon,
    required this.cor,
  });
}
