import 'package:flutter/material.dart';
import 'package:pole_price/models/product_group_model.dart';
import 'package:pole_price/screens/preco_screen.dart';
import 'package:pole_price/service/product_group_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/sidebar.dart';

class GruposScreen extends StatefulWidget {
  const GruposScreen({super.key});

  @override
  State<GruposScreen> createState() => _GruposScreenState();
}

class _GruposScreenState extends State<GruposScreen> {
  static const _laranja = Color(0xFFFF6B00);

  late final ProductGroupService _service;

  bool _loading = true;
  List<ProductCategory> _categorias = [];

  // Nó selecionado na árvore
  PricingCluster? _clusterSelecionado;
  ProductGroup? _grupoSelecionado;

  // Produtos do cluster selecionado
  List<ClusterProduct> _produtos = [];
  bool _loadingProdutos = false;

  // Expansão da árvore
  final Set<String> _categoriasAbertas = {};
  final Set<String> _linhasAbertas = {};
  final Set<String> _gruposAbertos = {};

  @override
  void initState() {
    super.initState();
    _service = ProductGroupService(Supabase.instance.client);
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final cats = await _service.getHierarchy();
      setState(() {
        _categorias = cats;
        _loading = false;
        // Expande primeira categoria automaticamente
        if (cats.isNotEmpty) _categoriasAbertas.add(cats.first.id);
      });
    } catch (e) {
      setState(() => _loading = false);
      _snack('Erro ao carregar hierarquia: $e', erro: true);
    }
  }

  Future<void> _selecionarCluster(
      PricingCluster cluster, ProductGroup grupo) async {
    setState(() {
      _clusterSelecionado = cluster;
      _grupoSelecionado = grupo;
      _produtos = [];
      _loadingProdutos = true;
    });

    try {
      final produtos = await _service.getProductsByCluster(cluster.id);
      setState(() {
        _produtos = produtos;
        _loadingProdutos = false;
      });
    } catch (e) {
      setState(() => _loadingProdutos = false);
      _snack('Erro ao carregar produtos: $e', erro: true);
    }
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: erro ? Colors.red : Colors.green,
    ));
  }

  // ── BUILD ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Row(
        children: [
          const Sidebar(paginaAtiva: 'grupos'),
          Expanded(
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _categorias.isEmpty
                          ? _vazio()
                          : Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // PAINEL ESQUERDO — árvore de hierarquia
                                  SizedBox(
                                    width: 320,
                                    child: _arvore(),
                                  ),
                                  const SizedBox(width: 20),
                                  // PAINEL DIREITO — produtos do cluster
                                  Expanded(child: _painelDireito()),
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
            'Grupos de Materiais',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Recarregar',
            onPressed: _carregar,
            color: Colors.grey.shade600,
          ),
        ],
      ),
    );
  }

  // ── ÁRVORE ──────────────────────────────────────────────────────────

  Widget _arvore() {
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined,
                    size: 16, color: _laranja),
                const SizedBox(width: 8),
                const Text(
                  'Hierarquia',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '${_categorias.length} categorias',
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: _categorias
                  .map((cat) => _noCategoria(cat))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noCategoria(ProductCategory cat) {
    final aberta = _categoriasAbertas.contains(cat.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => aberta
              ? _categoriasAbertas.remove(cat.id)
              : _categoriasAbertas.add(cat.id)),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  aberta
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 18,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.folder_outlined,
                    size: 16, color: _laranja),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cat.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _badge('${cat.totalSkus}'),
              ],
            ),
          ),
        ),
        if (aberta)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              children: cat.lines
                  .map((line) => _noLinha(line))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _noLinha(ProductLine line) {
    final aberta = _linhasAbertas.contains(line.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => aberta
              ? _linhasAbertas.remove(line.id)
              : _linhasAbertas.add(line.id)),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                Icon(
                  aberta
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Icon(Icons.layers_outlined,
                    size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line.name,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade800),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _badge('${line.totalSkus}', small: true),
              ],
            ),
          ),
        ),
        if (aberta)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              children: line.groups
                  .map((group) => _noGrupo(group))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _noGrupo(ProductGroup group) {
    final aberto = _gruposAbertos.contains(group.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => aberto
              ? _gruposAbertos.remove(group.id)
              : _gruposAbertos.add(group.id)),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  aberto
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Icon(Icons.category_outlined,
                    size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.name,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _badge('${group.totalSkus}', small: true),
              ],
            ),
          ),
        ),
        if (aberto)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              children: group.clusters
                  .map((cluster) => _noCluster(cluster, group))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _noCluster(PricingCluster cluster, ProductGroup grupo) {
    final selecionado = _clusterSelecionado?.id == cluster.id;
    return InkWell(
      onTap: () => _selecionarCluster(cluster, grupo),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selecionado
              ? _laranja.withOpacity(0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: selecionado
              ? Border.all(color: _laranja.withOpacity(0.3))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.grain,
              size: 12,
              color: selecionado ? _laranja : Colors.grey.shade400,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                cluster.name,
                style: TextStyle(
                  fontSize: 12,
                  color: selecionado ? _laranja : Colors.grey.shade700,
                  fontWeight: selecionado
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _badge('${cluster.skuCount}',
                small: true, destaque: selecionado),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label,
      {bool small = false, bool destaque = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: destaque
            ? _laranja.withOpacity(0.15)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: small ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: destaque ? _laranja : Colors.grey.shade600,
        ),
      ),
    );
  }

  // ── PAINEL DIREITO ───────────────────────────────────────────────────

  Widget _painelDireito() {
    if (_clusterSelecionado == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                'Selecione um agrupamento',
                style: TextStyle(
                    color: Colors.grey.shade500, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Os materiais do cluster aparecerão aqui',
                style: TextStyle(
                    color: Colors.grey.shade400, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header do painel
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _clusterSelecionado!.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _grupoSelecionado?.name ?? '',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                // Botão ação: ir para preços filtrado por cluster
                OutlinedButton.icon(
                  icon: const Icon(Icons.attach_money, size: 16),
                  label: const Text('Editar preços'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _laranja,
                    side: const BorderSide(color: _laranja),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PrecoScreen(
                          filtroClusterId: _clusterSelecionado!.id,
                          filtroClusterNome: _clusterSelecionado!.name,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Cabeçalho da tabela
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 10),
            color: Colors.grey.shade50,
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Código',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Text(
                    'Descrição',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    'CPV',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Lista de produtos
          Expanded(
            child: _loadingProdutos
                ? const Center(child: CircularProgressIndicator())
                : _produtos.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum produto neste cluster',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _produtos.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final p = _produtos[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    p.code,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    p.description,
                                    style:
                                        const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    p.cpv != null
                                        ? 'R\$ ${p.cpv!.toStringAsFixed(2)}'
                                        : '—',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: p.cpv != null
                                          ? Colors.grey.shade700
                                          : Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // Footer com total
          if (_produtos.isNotEmpty && !_loadingProdutos)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border:
                    Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Text(
                '${_produtos.length} materiais neste agrupamento',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
  }

  Widget _vazio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.layers_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'Nenhuma hierarquia encontrada',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}