import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/pricing_cluster_item.dart';
import 'package:pole_price/models/regra_ajuste.dart';

const _laranja = Color(0xFFFF6B00);

class SecaoExcecoes extends StatefulWidget {
  final PrecoController controller;
  const SecaoExcecoes({super.key, required this.controller});

  @override
  State<SecaoExcecoes> createState() => _SecaoExcecoesState();
}

class _SecaoExcecoesState extends State<SecaoExcecoes> {
  String _nivel = 'Tabela';
  String _tipo = 'Percentual';
  String? _listaExcecaoSelecionada;
  PricingClusterItem? _clusterSelecionado;
  String? _materialSelecionado;
  final _valorController = TextEditingController();

  PrecoController get c => widget.controller;

  @override
  void dispose() {
    _valorController.dispose();
    super.dispose();
  }

  bool _podeAdicionarRegra() {
    if (_listaExcecaoSelecionada == null) return false;
    if (_valorController.text.isEmpty) return false;
    if (_nivel == 'Grupo' && _clusterSelecionado == null) return false;
    if (_nivel == 'Material' && (_clusterSelecionado == null || _materialSelecionado == null)) {
      return false;
    }
    return true;
  }

  String _nomeCluster(String? id) {
    if (id == null) return '';
    return c.clusters.where((cl) => cl.id == id).map((cl) => cl.name).firstOrNull ?? id;
  }

  @override
  Widget build(BuildContext context) {
    final listasParaExcecao = c.listas.where((l) => c.targets.contains(l.id)).toList();

    if (_listaExcecaoSelecionada != null && !c.targets.contains(_listaExcecaoSelecionada)) {
      _listaExcecaoSelecionada = null;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _numeroBadge('3'),
              const SizedBox(width: 10),
              const Text(
                'Exceções e ajustes',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (listasParaExcecao.isEmpty)
            _aviso(
              'Selecione pelo menos uma lista destino na seção acima para configurar exceções.',
              icon: Icons.info_outline,
              cor: Colors.grey.shade500,
              bg: Colors.grey.shade50,
              border: Colors.grey.shade200,
            )
          else ...[
            DropdownButtonFormField<String>(
              value: _listaExcecaoSelecionada,
              isExpanded: true,
              decoration: _inputDeco('Selecione a lista para configurar exceções'),
              items: listasParaExcecao
                  .map((l) => DropdownMenuItem(value: l.id, child: Text(l.description)))
                  .toList(),
              onChanged: (v) => setState(() => _listaExcecaoSelecionada = v),
            ),
            const SizedBox(height: 14),

            const Text(
              'Nível da exceção',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _cardNivel(
                    id: 'Tabela',
                    label: 'Tabela inteira',
                    sub: 'Aplicar para todos os materiais',
                    icon: Icons.table_rows_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _cardNivel(
                    id: 'Grupo',
                    label: 'Grupo de material',
                    sub: 'Aplicar para um grupo específico',
                    icon: Icons.account_tree_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _cardNivel(
                    id: 'Material',
                    label: 'Material específico',
                    sub: 'Aplicar para materiais específicos',
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_nivel == 'Grupo' || _nivel == 'Material') ...[
              c.loadingClusters
                  ? const LinearProgressIndicator()
                  : DropdownButtonFormField<PricingClusterItem>(
                      value: _clusterSelecionado,
                      isExpanded: true,
                      decoration: _inputDeco('Agrupamento'),
                      items: c.clusters
                          .map((cl) => DropdownMenuItem(value: cl, child: Text(cl.name)))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _clusterSelecionado = v;
                          _materialSelecionado = null;
                        });
                        if (_nivel == 'Material' && v != null) {
                          c.carregarMateriaisDoCluster(v.id);
                        }
                      },
                    ),
              const SizedBox(height: 8),
            ],

            if (_nivel == 'Material' && _clusterSelecionado != null) ...[
              c.loadingMateriaisCluster
                  ? const LinearProgressIndicator()
                  : DropdownButtonFormField<String>(
                      value: _materialSelecionado,
                      isExpanded: true,
                      decoration: _inputDeco('Material'),
                      items: c.materiaisDoCluster
                          .map((m) => DropdownMenuItem(
                                value: m.codigo,
                                child: Text(m.description, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _materialSelecionado = v),
                    ),
              const SizedBox(height: 8),
            ],

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _tipo,
                    isExpanded: true,
                    decoration: _inputDeco('Tipo de ajuste'),
                    items: ['Percentual', 'Fixo']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setState(() => _tipo = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _valorController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _inputDeco('Valor do ajuste').copyWith(
                      suffixText: _tipo == 'Percentual' ? '%' : 'R\$',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_listaExcecaoSelecionada != null && _valorController.text.isNotEmpty)
              _resumoRegra(),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18, color: _laranja),
                label: const Text('Adicionar exceção', style: TextStyle(color: _laranja)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _laranja),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _podeAdicionarRegra()
                    ? () {
                        final valor = double.tryParse(_valorController.text) ?? 0;
                        c.addRegra(RegraAjuste(
                          targetListId: _listaExcecaoSelecionada!,
                          nivel: _nivel,
                          tipo: _tipo,
                          valor: valor,
                          clusterId: _clusterSelecionado?.id,
                          clusterNome: _clusterSelecionado?.name,
                          materialId: _nivel == 'Material' ? _materialSelecionado : null,
                          materialNome: _nivel == 'Material'
                              ? c.materiaisDoCluster
                                  .where((m) => m.codigo == _materialSelecionado)
                                  .map((m) => m.description)
                                  .firstOrNull
                              : null,
                        ));
                        setState(() {
                          _valorController.clear();
                          _listaExcecaoSelecionada = null;
                          _clusterSelecionado = null;
                          _materialSelecionado = null;
                          _nivel = 'Tabela';
                        });
                      }
                    : null,
              ),
            ),
          ],

          if (c.regras.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Regras configuradas (${c.regras.length})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _tabelaRegras(),
          ],
        ],
      ),
    );
  }

  Widget _tabelaRegras() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                _th('Nível', flex: 2),
                _th('Descrição', flex: 3),
                _thRight('Ajuste', width: 60),
                const SizedBox(width: 40),
              ],
            ),
          ),
          const Divider(height: 1),
          ...c.regras.asMap().entries.map((entry) {
            final i = entry.key;
            final r = entry.value;
            final nomeLista = c.listas
                    .where((l) => l.id == r.targetListId)
                    .map((l) => l.description)
                    .firstOrNull ?? r.targetListId;
            final descricao = r.nivel == 'Grupo'
                ? _nomeCluster(r.clusterId)
                : r.nivel == 'Material'
                ? r.materialId ?? ''
                : nomeLista;
            final sinal = r.valor >= 0 ? '+' : '';
            final ajusteStr =
                '$sinal${r.valor.toStringAsFixed(2)}${r.tipo == 'Percentual' ? '%' : ' R\$'}';

            return Column(
              children: [
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text(r.nivel, style: const TextStyle(fontSize: 12))),
                      Expanded(
                        flex: 3,
                        child: Text(descricao,
                            style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(
                          ajusteStr,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: r.valor >= 0 ? Colors.green : Colors.red,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => c.removeRegra(r),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _cardNivel({
    required String id,
    required String label,
    required String sub,
    required IconData icon,
  }) {
    final ativo = _nivel == id;
    return GestureDetector(
      onTap: () {
        setState(() {
          _nivel = id;
          _clusterSelecionado = null;
          _materialSelecionado = null;
          c.materiaisDoCluster = [];
        });
        if (id == 'Grupo' || id == 'Material') c.carregarClusters();
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: ativo ? _laranja.withOpacity(0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: ativo ? _laranja : Colors.grey.shade200,
            width: ativo ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: ativo ? _laranja : Colors.grey.shade500),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ativo ? _laranja : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _resumoRegra() {
    final nomeLista = c.listas
            .where((l) => l.id == _listaExcecaoSelecionada)
            .map((l) => l.description)
            .firstOrNull ?? _listaExcecaoSelecionada!;
    final sufixo = _tipo == 'Percentual' ? '%' : ' R\$';
    final nivelDesc = _nivel == 'Grupo'
        ? 'no grupo ${_nomeCluster(_clusterSelecionado?.id)}'
        : _nivel == 'Material'
        ? 'no material ${_materialSelecionado ?? ''}'
        : 'em toda a tabela';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _laranja.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _laranja.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.summarize_outlined, size: 16, color: _laranja),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'A lista $nomeLista terá um acréscimo de ${_valorController.text}$sufixo $nivelDesc.',
              style: const TextStyle(fontSize: 11, color: _laranja),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aviso(
    String msg, {
    required IconData icon,
    required Color cor,
    required Color bg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cor),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: TextStyle(fontSize: 12, color: cor))),
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
    );
  }

  Widget _th(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
      ),
    );
  }

  Widget _thRight(String label, {required double width}) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
      ),
    );
  }

  Widget _numeroBadge(String n) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: _laranja, borderRadius: BorderRadius.circular(6)),
      child: Center(
        child: Text(
          n,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }
}