import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/material_preco.dart';
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
  MaterialPreco? _materialSelecionado;
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
    if (_nivel == 'Material' && _materialSelecionado == null) return false;
    return true;
  }

  String _nomeCluster(String? id) {
    if (id == null) return '';
    return c.clusters
            .where((cl) => cl.id == id)
            .map((cl) => cl.name)
            .firstOrNull ??
        id;
  }

  // ── Abre dialog de busca de cluster ──────────────────────────────────────

  Future<void> _abrirPickerCluster() async {
    if (c.clusters.isEmpty) await c.carregarClusters();
    if (!mounted) return;

    print('Total materiais: ${c.materiais.length}');
    print(
      'Com clusterId: ${c.materiais.where((m) => m.clusterId != null).length}',
    );
    print('Clusters carregados: ${c.clusters.length}');

    // Apenas clusters que têm ao menos um material na sessão atual
    final clusterIdsDaSessao = c.materiais
        .where((m) => !m.removido && m.clusterId != null)
        .map((m) => m.clusterId!)
        .toSet();

    print('IDs encontrados: $clusterIdsDaSessao');
    final clustersFiltrados = c.clusters
        .where((cl) => clusterIdsDaSessao.contains(cl.id))
        .toList();

    final result = await showDialog<PricingClusterItem>(
      context: context,
      builder: (_) => _ClusterPickerDialog(clusters: clustersFiltrados),
    );

    if (result != null) {
      setState(() {
        _clusterSelecionado = result;
        _materialSelecionado = null;
        c.materiaisDoCluster = [];
      });
      if (_nivel == 'Material') {
        await c.carregarMateriaisDoCluster(result.id);
        setState(() {});
      }
    }
  }

  // ── Abre dialog de busca de material ─────────────────────────────────────

  Future<void> _abrirPickerMaterial() async {
    final materiais = c.materiais.where((m) => !m.removido).toList();
    if (!mounted) return;

    final result = await showDialog<MaterialPreco>(
      context: context,
      builder: (_) => _MaterialPickerDialog(materiais: materiais),
    );

    if (result != null) {
      setState(() => _materialSelecionado = result);
    }
  }

  // ── Build principal ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final listasParaExcecao = c.listas
        .where((l) => c.targets.contains(l.id))
        .toList();

    if (_listaExcecaoSelecionada != null &&
        !c.targets.contains(_listaExcecaoSelecionada)) {
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
            // ── Seleção de lista ────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _listaExcecaoSelecionada,
              isExpanded: true,
              decoration: _inputDeco('Lista para configurar exceções'),
              items: listasParaExcecao
                  .map(
                    (l) => DropdownMenuItem(
                      value: l.id,
                      child: Text(l.description),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _listaExcecaoSelecionada = v),
            ),
            const SizedBox(height: 14),

            // ── Cards de nível ──────────────────────────────────────
            const Text(
              'Nível da exceção',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _cardNivel(
                    id: 'Tabela',
                    label: 'Tabela inteira',
                    sub: 'Todos os materiais',
                    icon: Icons.table_rows_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _cardNivel(
                    id: 'Grupo',
                    label: 'Grupo de material',
                    sub: 'Um grupo específico',
                    icon: Icons.account_tree_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _cardNivel(
                    id: 'Material',
                    label: 'Material específico',
                    sub: 'Um material do grupo',
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Picker de cluster (só nível Grupo) ──────────────────
            if (_nivel == 'Grupo') ...[
              _PickerField(
                label: 'Agrupamento',
                icon: Icons.account_tree_outlined,
                loading: c.loadingClusters,
                codigo: null,
                nome: _clusterSelecionado?.name,
                placeholder: 'Selecionar agrupamento...',
                onTap: _abrirPickerCluster,
                onClear: () => setState(() {
                  _clusterSelecionado = null;
                  c.materiaisDoCluster = [];
                }),
              ),
              const SizedBox(height: 8),
            ],

            // ── Picker de material (nível Material — direto da sessão) ─
            if (_nivel == 'Material') ...[
              _PickerField(
                label: 'Material',
                icon: Icons.inventory_2_outlined,
                loading: false,
                codigo: _materialSelecionado?.codigo,
                nome: _materialSelecionado?.description,
                placeholder: 'Selecionar material...',
                onTap: _abrirPickerMaterial,
                onClear: () => setState(() => _materialSelecionado = null),
              ),
              const SizedBox(height: 8),
            ],

            // ── Tipo + Valor ────────────────────────────────────────
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
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _inputDeco(
                      'Valor do ajuste',
                    ).copyWith(suffixText: _tipo == 'Percentual' ? '%' : 'R\$'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_listaExcecaoSelecionada != null &&
                _valorController.text.isNotEmpty)
              _resumoRegra(),

            const SizedBox(height: 12),

            // ── Botão adicionar ─────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18, color: _laranja),
                label: const Text(
                  'Adicionar exceção',
                  style: TextStyle(color: _laranja),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _laranja),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _podeAdicionarRegra()
                    ? () {
                        final valor =
                            double.tryParse(_valorController.text) ?? 0;
                        c.addRegra(
                          RegraAjuste(
                            targetListId: _listaExcecaoSelecionada!,
                            nivel: _nivel,
                            tipo: _tipo,
                            valor: valor,
                            clusterId: _nivel == 'Grupo'
                                ? _clusterSelecionado?.id
                                : null,
                            clusterNome: _nivel == 'Grupo'
                                ? _clusterSelecionado?.name
                                : null,
                            materialId: _nivel == 'Material'
                                ? _materialSelecionado?.codigo
                                : null,
                            materialNome: _nivel == 'Material'
                                ? _materialSelecionado?.description
                                : null,
                          ),
                        );
                        setState(() {
                          _valorController.clear();
                          _listaExcecaoSelecionada = null;
                          _clusterSelecionado = null;
                          _materialSelecionado = null;
                          _nivel = 'Tabela';
                          c.materiaisDoCluster = [];
                        });
                      }
                    : null,
              ),
            ),
          ],

          // ── Tabela de regras ──────────────────────────────────────
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

  // ── Tabela de regras ──────────────────────────────────────────────────────

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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                _th('Lista', flex: 3),
                _th('Nível', flex: 2),
                _th('Descrição', flex: 4),
                _thRight('Ajuste', width: 60),
                const SizedBox(width: 40),
              ],
            ),
          ),
          const Divider(height: 1),
          ...c.regras.asMap().entries.map((entry) {
            final i = entry.key;
            final r = entry.value;
            final nomeLista =
                c.listas
                    .where((l) => l.id == r.targetListId)
                    .map((l) => l.description)
                    .firstOrNull ??
                r.targetListId;
            final sinal = r.valor >= 0 ? '+' : '';
            final ajusteStr =
                '$sinal${r.valor.toStringAsFixed(2)}${r.tipo == 'Percentual' ? '%' : ' R\$'}';

            return Column(
              children: [
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          nomeLista,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          r.nivel,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: r.nivel == 'Material'
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (r.materialId != null)
                                    Text(
                                      r.materialId!,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                        color: Color(0xFF9E9E9E),
                                      ),
                                    ),
                                  Text(
                                    r.materialNome ?? r.materialId ?? '',
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              )
                            : Text(
                                r.nivel == 'Grupo'
                                    ? _nomeCluster(r.clusterId)
                                    : 'Toda a tabela',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
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
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: Colors.red,
                        ),
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

  // ── Widgets auxiliares ────────────────────────────────────────────────────

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
        if (id == 'Grupo') c.carregarClusters();
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
            Icon(
              icon,
              size: 18,
              color: ativo ? _laranja : Colors.grey.shade500,
            ),
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
            Text(
              sub,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumoRegra() {
    final nomeLista =
        c.listas
            .where((l) => l.id == _listaExcecaoSelecionada)
            .map((l) => l.description)
            .firstOrNull ??
        _listaExcecaoSelecionada!;
    final sufixo = _tipo == 'Percentual' ? '%' : ' R\$';
    final nivelDesc = _nivel == 'Grupo'
        ? 'no grupo ${_nomeCluster(_clusterSelecionado?.id)}'
        : _nivel == 'Material'
        ? 'no material ${_materialSelecionado?.codigo ?? ''} — ${_materialSelecionado?.description ?? ''}'
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
          Expanded(
            child: Text(msg, style: TextStyle(fontSize: 12, color: cor)),
          ),
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

  Widget _th(String label, {int flex = 1}) => Expanded(
    flex: flex,
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
      ),
    ),
  );

  Widget _thRight(String label, {required double width}) => SizedBox(
    width: width,
    child: Text(
      label,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
      ),
    ),
  );

  Widget _numeroBadge(String n) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      color: _laranja,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Center(
      child: Text(
        n,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    ),
  );
}

// ── Widget de campo picker (botão que abre dialog) ────────────────────────────

class _PickerField extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final String? codigo;
  final String? nome;
  final String placeholder;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _PickerField({
    required this.label,
    required this.icon,
    required this.loading,
    required this.codigo,
    required this.nome,
    required this.placeholder,
    required this.onTap,
    required this.onClear,
    this.enabled = true,
  });

  bool get _temValor => nome != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: enabled && !loading ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: enabled ? Colors.white : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _temValor
                    ? _laranja.withOpacity(0.4)
                    : Colors.grey.shade300,
              ),
            ),
            child: loading
                ? const SizedBox(
                    height: 20,
                    child: LinearProgressIndicator(color: _laranja),
                  )
                : Row(
                    children: [
                      Icon(
                        _temValor ? icon : Icons.search,
                        size: 16,
                        color: _temValor ? _laranja : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _temValor
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (codigo != null)
                                    Text(
                                      codigo!,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                        color: Color(0xFF9E9E9E),
                                      ),
                                    ),
                                  Text(
                                    nome!,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF212121),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              )
                            : Text(
                                placeholder,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                      ),
                      if (_temValor)
                        GestureDetector(
                          onTap: onClear,
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.grey.shade400,
                          ),
                        )
                      else
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Colors.grey.shade400,
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

// ── Dialog de busca de cluster ────────────────────────────────────────────────

class _ClusterPickerDialog extends StatefulWidget {
  final List<PricingClusterItem> clusters;
  const _ClusterPickerDialog({required this.clusters});

  @override
  State<_ClusterPickerDialog> createState() => _ClusterPickerDialogState();
}

class _ClusterPickerDialogState extends State<_ClusterPickerDialog> {
  String _pesquisa = '';

  List<PricingClusterItem> get _filtrados => widget.clusters
      .where(
        (cl) =>
            cl.name.toLowerCase().contains(_pesquisa.toLowerCase()) ||
            cl.id.toLowerCase().contains(_pesquisa.toLowerCase()),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 460,
        height: 500,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
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
                    child: const Icon(
                      Icons.account_tree_outlined,
                      color: _laranja,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selecionar agrupamento',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Grupos de materiais disponíveis',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: Color(0xFF9E9E9E),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Busca
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Buscar agrupamento...',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFBDBDBD),
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 18,
                    color: Color(0xFF9E9E9E),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8F8F8),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
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
                onChanged: (v) => setState(() => _pesquisa = v),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${filtrados.length} agrupamento${filtrados.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9E9E9E),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),

            // Lista
            Expanded(
              child: filtrados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 32,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Nenhum agrupamento encontrado',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      itemCount: filtrados.length,
                      itemBuilder: (_, i) {
                        final cl = filtrados[i];
                        return InkWell(
                          onTap: () => Navigator.pop(context, cl),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: _laranja.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.account_tree_outlined,
                                    size: 16,
                                    color: _laranja,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cl.name,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        'ID: ${cl.id}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF9E9E9E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: Color(0xFFCCCCCC),
                                ),
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

// ── Dialog de busca de material ───────────────────────────────────────────────

class _MaterialPickerDialog extends StatefulWidget {
  final List<MaterialPreco> materiais;
  const _MaterialPickerDialog({required this.materiais});

  @override
  State<_MaterialPickerDialog> createState() => _MaterialPickerDialogState();
}

class _MaterialPickerDialogState extends State<_MaterialPickerDialog> {
  String _pesquisa = '';

  List<MaterialPreco> get _filtrados => widget.materiais
      .where(
        (m) =>
            m.codigo.toLowerCase().contains(_pesquisa.toLowerCase()) ||
            m.description.toLowerCase().contains(_pesquisa.toLowerCase()),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 460,
        height: 500,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
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
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: _laranja,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selecionar material',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Materiais do agrupamento selecionado',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: Color(0xFF9E9E9E),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Busca
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Buscar por código ou descrição...',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFBDBDBD),
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 18,
                    color: Color(0xFF9E9E9E),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8F8F8),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
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
                onChanged: (v) => setState(() => _pesquisa = v),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${filtrados.length} material${filtrados.length != 1 ? 'is' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9E9E9E),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),

            // Lista
            Expanded(
              child: filtrados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 32,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Nenhum material encontrado',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      itemCount: filtrados.length,
                      itemBuilder: (_, i) {
                        final m = filtrados[i];
                        return InkWell(
                          onTap: () => Navigator.pop(context, m),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0F0F0),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    m.codigo,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: Color(0xFF616161),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    m.description,
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: Color(0xFFCCCCCC),
                                ),
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
