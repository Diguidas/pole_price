import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/pricing_cluster_item.dart';
import 'package:pole_price/models/regra_ajuste.dart';
import 'package:pole_price/service/preco_service.dart';
import 'package:pole_price/widgets/sidebar.dart';
import 'package:pole_price/widgets/tabela_precos.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PrecoScreen extends StatefulWidget {
  final String? filtroClusterId;
  final String? filtroClusterNome;

  const PrecoScreen({super.key, this.filtroClusterId, this.filtroClusterNome});

  @override
  State<PrecoScreen> createState() => _PrecoScreenState();
}

class _PrecoScreenState extends State<PrecoScreen> {
  static const _laranja = Color(0xFFFF6B00);

  late PrecoController controller;

  @override
  void initState() {
    super.initState();
    final service = PriceService(Supabase.instance.client);
    controller = PrecoController(service);
    // FIX 3: escuta o controller para reconstruir toda a tela (incluindo lista de regras)
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    controller.init().then((_) {
      if (widget.filtroClusterId != null) {
        controller.filtrarPorCluster(widget.filtroClusterId!);
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Row(
        children: [
          const Sidebar(paginaAtiva: 'precos'),
          Expanded(
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: controller.loading
                      ? const Center(child: CircularProgressIndicator())
                      : Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: _painelEsquerdo()),
                              const SizedBox(width: 20),
                              SizedBox(width: 380, child: _painelDireito()),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TOP BAR ─────────────────────────────────────────────────────────

  Widget _topBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          const Text(
            'Gestão de Preços',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Salvar para aprovação'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _laranja,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: controller.selecionada == null
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Confirmar'),
                        content: const Text(
                          'Deseja enviar este rascunho para aprovação?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Salvar'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        await controller.salvar();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Rascunho salvo com sucesso!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Erro ao salvar: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
          ),
        ],
      ),
    );
  }

  // ── PAINEL ESQUERDO ─────────────────────────────────────────────────

  Widget _painelEsquerdo() {
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
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _numeroBadge('1'),
                    const SizedBox(width: 10),
                    const Text(
                      'Lista mãe (base)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField(
                  value: controller.selecionada,
                  decoration: InputDecoration(
                    labelText: 'Tabela de Preço',
                    prefixIcon: const Icon(
                      Icons.table_chart_outlined,
                      color: Color(0xFFFF6B00),
                    ),
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
                  ),
                  items: controller.listas.map((l) {
                    return DropdownMenuItem(
                      value: l,
                      child: Text(l.description),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) controller.selecionarLista(val);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar material...',
                    prefixIcon: const Icon(Icons.search, size: 20),
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  onChanged: controller.buscar,
                ),
              ],
            ),
          ),

          if (controller.selecionada != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  _colHeader('Código', flex: 2),
                  _colHeader('Descrição do Material', flex: 5),
                  _colHeader(
                    'Preço Atual (R\$)',
                    flex: 2,
                    align: TextAlign.right,
                  ),
                  _colHeader(
                    'Novo Preço (R\$)',
                    flex: 2,
                    align: TextAlign.right,
                  ),
                  _colHeader('Margem (%)', flex: 2, align: TextAlign.right),
                ],
              ),
            ),

          Expanded(child: TabelaPrecos(controller: controller)),

          if (controller.selecionada != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Text(
                'Exibindo ${controller.filtrados.length} de ${controller.materiais.length} materiais',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
  }

  Widget _colHeader(
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
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  // ── PAINEL DIREITO ───────────────────────────────────────────────────

  Widget _painelDireito() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _secaoListasDestino(),
          const SizedBox(height: 16),
          _secaoExcecoes(),
        ],
      ),
    );
  }

  // ── SEÇÃO 2: Listas destino ──────────────────────────────────────────

  Widget _secaoListasDestino() {
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
              _numeroBadge('2'),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Listas que receberão os preços da lista mãe',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (controller.targets.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: controller.targets.map((id) {
                final nome =
                    controller.listas
                        .where((l) => l.id == id)
                        .map((l) => l.description)
                        .firstOrNull ??
                    id;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _laranja.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _laranja.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _laranja,
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => controller.toggleTarget(id),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: _laranja,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    controller.targets.length,
                  ), // força rebuild ao mudar targets
                  decoration: InputDecoration(
                    labelText: 'Selecionar listas de preço',
                    prefixIcon: const Icon(Icons.add_circle_outline, size: 20),
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
                  ),
                  isExpanded: true,
                  value: null,
                  items: controller.listas
                      .where(
                        (l) =>
                            l.id != controller.selecionada?.id &&
                            !controller.targets.contains(l.id),
                      )
                      .map(
                        (l) => DropdownMenuItem(
                          value: l.id,
                          child: Text(l.description),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) controller.toggleTarget(val);
                  },
                ),
              ),
            ],
          ),

          if (controller.targets.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.blue.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'As listas selecionadas receberão os preços da lista mãe conforme as exceções e ajustes configurados abaixo.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── SEÇÃO 3: Exceções e ajustes ──────────────────────────────────────

  String _nivel = 'Tabela';
  String _tipo = 'Percentual';
  String? _listaExcecaoSelecionada;
  PricingClusterItem? _clusterSelecionado;
  String? _materialSelecionado;
  final _valorController = TextEditingController();

  Widget _secaoExcecoes() {
    // FIX 2: só mostra as listas que foram selecionadas como targets
    final listasParaExcecao = controller.listas
        .where((l) => controller.targets.contains(l.id))
        .toList();

    // Se a lista selecionada para exceção não está mais nos targets, limpa
    if (_listaExcecaoSelecionada != null &&
        !controller.targets.contains(_listaExcecaoSelecionada)) {
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Selecione pelo menos uma lista destino na seção acima para configurar exceções.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            DropdownButtonFormField<String>(
              value: _listaExcecaoSelecionada,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Selecione a lista para configurar exceções',
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
              ),
              // FIX 2: somente as listas que estão em targets
              items: listasParaExcecao.map((l) {
                return DropdownMenuItem(
                  value: l.id,
                  child: Text(l.description),
                );
              }).toList(),
              onChanged: (v) => setState(() => _listaExcecaoSelecionada = v),
            ),
            const SizedBox(height: 14),

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
              controller.loadingClusters
                  ? const LinearProgressIndicator()
                  : DropdownButtonFormField<PricingClusterItem>(
                      value: _clusterSelecionado,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Agrupamento',
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
                      ),
                      items: controller.clusters.map((c) {
                        return DropdownMenuItem(value: c, child: Text(c.name));
                      }).toList(),
                      onChanged: (v) {
                        setState(() {
                          _clusterSelecionado = v;
                          _materialSelecionado = null;
                        });
                        if (_nivel == 'Material' && v != null) {
                          controller.carregarMateriaisDoCluster(v.id);
                        }
                      },
                    ),
              const SizedBox(height: 8),
            ],

            if (_nivel == 'Material' && _clusterSelecionado != null) ...[
              controller.loadingMateriaisCluster
                  ? const LinearProgressIndicator()
                  : DropdownButtonFormField<String>(
                      value: _materialSelecionado,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Material',
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
                      ),
                      items: controller.materiaisDoCluster.map((m) {
                        return DropdownMenuItem(
                          value: m.codigo,
                          child: Text(
                            m.description,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) =>
                          setState(() => _materialSelecionado = v),
                    ),
              const SizedBox(height: 8),
            ],

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _tipo,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Tipo de ajuste',
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
                    ),
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
                    decoration: InputDecoration(
                      labelText: 'Valor do ajuste',
                      suffixText: _tipo == 'Percentual' ? '%' : 'R\$',
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
                    ),
                    // FIX 3: rebuild ao digitar para habilitar/desabilitar botão
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
                        controller.addRegra(
                          RegraAjuste(
                            targetListId: _listaExcecaoSelecionada!,
                            nivel: _nivel,
                            tipo: _tipo,
                            valor: valor,
                            clusterId: _clusterSelecionado?.id,
                            clusterNome: _clusterSelecionado?.name, // ← novo
                            materialId: _nivel == 'Material'
                                ? _materialSelecionado
                                : null,
                            materialNome:
                                _nivel ==
                                    'Material' // ← novo
                                ? controller.materiaisDoCluster
                                      .where(
                                        (m) => m.codigo == _materialSelecionado,
                                      )
                                      .map((m) => m.description)
                                      .firstOrNull
                                : null,
                          ),
                        );
                        // FIX 3: limpa campos locais e força rebuild
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

          // FIX 3: lista de regras sempre renderizada (fora do else),
          // reage ao controller via setState no addListener do initState
          if (controller.regras.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Regras configuradas (${controller.regras.length})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Nível',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Descrição',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            'Ajuste',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ...controller.regras.asMap().entries.map((entry) {
                    final i = entry.key;
                    final r = entry.value;
                    final nomeLista =
                        controller.listas
                            .where((l) => l.id == r.targetListId)
                            .map((l) => l.description)
                            .firstOrNull ??
                        r.targetListId;
                    final descricao = r.nivel == 'Grupo'
                        ? _nomeCluster(r.clusterId)
                        : r.nivel == 'Material'
                        ? r.materialId ?? ''
                        : nomeLista;
                    final sinal = r.valor >= 0 ? '+' : '';
                    final ajusteStr =
                        '$sinal${r.valor.toStringAsFixed(2)}${r.tipo == 'Percentual' ? '%' : ' R\$'}';
                    final corAjuste = r.valor >= 0 ? Colors.green : Colors.red;

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
                                flex: 2,
                                child: Text(
                                  r.nivel,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  descricao,
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
                                    color: corAjuste,
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
                                onPressed: () => controller.removeRegra(r),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
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
          controller.materiaisDoCluster = [];
        });
        if (id == 'Grupo' || id == 'Material') {
          controller.carregarClusters();
        }
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
        controller.listas
            .where((l) => l.id == _listaExcecaoSelecionada)
            .map((l) => l.description)
            .firstOrNull ??
        _listaExcecaoSelecionada!;
    final valor = _valorController.text;
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
              'A lista $nomeLista terá um acréscimo de $valor$sufixo $nivelDesc.',
              style: const TextStyle(fontSize: 11, color: _laranja),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numeroBadge(String n) {
    return Container(
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

  bool _podeAdicionarRegra() {
    if (_listaExcecaoSelecionada == null) return false;
    if (_valorController.text.isEmpty) return false;
    if (_nivel == 'Grupo' && _clusterSelecionado == null) return false;
    if (_nivel == 'Material' &&
        (_clusterSelecionado == null || _materialSelecionado == null)) {
      return false;
    }
    return true;
  }

  String _nomeCluster(String? id) {
    if (id == null) return '';
    return controller.clusters
            .where((c) => c.id == id)
            .map((c) => c.name)
            .firstOrNull ??
        id;
  }
}
