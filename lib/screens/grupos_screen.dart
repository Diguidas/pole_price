import 'package:flutter/material.dart';
import 'package:pole_price/models/product_group_model.dart';
import 'package:pole_price/service/product_group_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GruposScreen extends StatefulWidget {
  const GruposScreen({super.key});

  @override
  State<GruposScreen> createState() => _GruposScreenState();
}

class _GruposScreenState extends State<GruposScreen> {
  static const _laranja = Color(0xFFFF6B00);
  static const _background = Color(0xFFF8F9FA);

  late final ProductGroupService _service;

  bool _loading = true;
  List<ProductCategory> _categorias = [];

  PricingCluster? _clusterSelecionado;
  ProductGroup? _grupoSelecionado;

  List<ClusterProduct> _produtos = [];
  bool _loadingProdutos = false;

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
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final cats = await _service.getHierarchy();
      if (!mounted) return;
      setState(() {
        _categorias = cats;
        _loading = false;
        if (cats.isNotEmpty) _categoriasAbertas.add(cats.first.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Erro ao carregar hierarquia: $e', erro: true);
    }
  }

  Future<void> _selecionarCluster(
    PricingCluster cluster,
    ProductGroup grupo,
  ) async {
    setState(() {
      _clusterSelecionado = cluster;
      _grupoSelecionado = grupo;
      _produtos = [];
      _loadingProdutos = true;
    });
    try {
      final produtos = await _service.getProductsByCluster(cluster.id);
      if (!mounted) return;
      setState(() {
        _produtos = produtos;
        _loadingProdutos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingProdutos = false);
      _snack('Erro ao carregar produtos: $e', erro: true);
    }
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              erro ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: erro ? Colors.red.shade800 : Colors.green.shade800,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  double? get _variacaoCpvMedia {
    final comCpv = _produtos.where((p) => p.cpv != null && p.cpv! > 0).toList();
    if (comCpv.isEmpty) return null;
    final media =
        comCpv.map((p) => p.cpv!).reduce((a, b) => a + b) / comCpv.length;
    final min = comCpv.map((p) => p.cpv!).reduce((a, b) => a < b ? a : b);
    if (media == 0) return null;
    return ((media - min) / media) * 100;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Column(
        children: [
          _topBar(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _laranja),
                  )
                : _categorias.isEmpty
                ? _vazio()
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 340, child: _arvore()),
                        const SizedBox(width: 24),
                        Expanded(child: _painelDireito()),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          const Text(
            'Grupos de Materiais',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Recarregar estrutura',
            onPressed: _carregar,
            color: Colors.grey.shade700,
          ),
        ],
      ),
    );
  }

  Widget _arvore() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.account_tree_outlined,
                  size: 18,
                  color: _laranja,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Hierarquia Comercial',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_categorias.length} Cats',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _categorias.length,
              itemBuilder: (context, index) => _noCategoria(_categorias[index]),
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
        _TreeTile(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          isOpen: aberta,
          onTap: () => setState(
            () => aberta
                ? _categoriasAbertas.remove(cat.id)
                : _categoriasAbertas.add(cat.id),
          ),
          leading: const Icon(Icons.folder_rounded, size: 18, color: _laranja),
          title: Text(
            cat.name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2D3748),
            ),
          ),
          trailing: Text(
            '${cat.totalSkus}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade400,
            ),
          ),
        ),
        if (aberta) ...cat.lines.map(_noLinha),
      ],
    );
  }

  Widget _noLinha(ProductLine linha) {
    final aberta = _linhasAbertas.contains(linha.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TreeTile(
          padding: const EdgeInsets.fromLTRB(24, 4, 12, 4),
          isOpen: aberta,
          onTap: () => setState(
            () => aberta
                ? _linhasAbertas.remove(linha.id)
                : _linhasAbertas.add(linha.id),
          ),
          leading: const Icon(
            Icons.layers_outlined,
            size: 16,
            color: Colors.blueGrey,
          ),
          title: Text(
            linha.name,
            style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568)),
          ),
          trailing: Text(
            '${linha.totalSkus}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ),
        if (aberta) ...linha.groups.map(_noGrupo),
      ],
    );
  }

  Widget _noGrupo(ProductGroup grupo) {
    final aberto = _gruposAbertos.contains(grupo.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TreeTile(
          padding: const EdgeInsets.fromLTRB(40, 4, 12, 4),
          isOpen: aberto,
          onTap: () => setState(
            () => aberto
                ? _gruposAbertos.remove(grupo.id)
                : _gruposAbertos.add(grupo.id),
          ),
          leading: Icon(
            Icons.grid_view_rounded,
            size: 15,
            color: Colors.grey.shade500,
          ),
          title: Text(
            grupo.name,
            style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568)),
          ),
          trailing: Text(
            '${grupo.totalSkus}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ),
        if (aberto) ...grupo.clusters.map((c) => _noCluster(c, grupo)),
      ],
    );
  }

  Widget _noCluster(PricingCluster cluster, ProductGroup grupo) {
    final selecionado = _clusterSelecionado?.id == cluster.id;
    return InkWell(
      onTap: () => _selecionarCluster(cluster, grupo),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.fromLTRB(48, 8, 12, 8),
        decoration: BoxDecoration(
          color: selecionado ? _laranja.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: selecionado ? _laranja : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                cluster.name,
                style: TextStyle(
                  fontSize: 12,
                  color: selecionado ? _laranja : const Color(0xFF718096),
                  fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${cluster.skuCount}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
                color: selecionado
                    ? _laranja.withOpacity(0.7)
                    : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
              Icon(
                Icons.ads_click_rounded,
                size: 56,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 16),
              Text(
                'Selecione um agrupamento',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Navegue na árvore ao lado para gerenciar os SKUs e custos.',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final semCpv = _produtos.where((p) => p.cpv == null).length;
    final comCpv = _produtos.where((p) => p.cpv != null).length;
    final variacao = _variacaoCpvMedia;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _clusterSelecionado!.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Grupo: ${_grupoSelecionado?.name ?? "—"}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!_loadingProdutos)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  _kpiCard(
                    icon: Icons.inventory_2_outlined,
                    label: 'MATERIAIS VINCULADOS',
                    valor: '${_produtos.length}',
                    sub: '$comCpv precificados · $semCpv pendentes',
                    cor: Colors.blue,
                  ),
                  const SizedBox(width: 16),
                  _kpiCard(
                    icon: Icons.analytics_outlined,
                    label: 'DISPERSÃO DE CUSTO (CPV)',
                    valor: variacao != null
                        ? '${variacao.toStringAsFixed(1)}%'
                        : '—',
                    sub: 'Desvio relativo interno',
                    cor: variacao != null && variacao > 20
                        ? Colors.amber
                        : Colors.teal,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Expanded(
            child: _loadingProdutos
                ? const Center(
                    child: CircularProgressIndicator(color: _laranja),
                  )
                : _produtos.isEmpty
                ? Center(
                    child: Text(
                      'Nenhum SKU associado a este agrupamento.',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  )
                : Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        color: Colors.grey.shade50,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _colHeader('CÓDIGO DE IDENTIFICAÇÃO'),
                            ),
                            Expanded(
                              flex: 5,
                              child: _colHeader('DESCRIÇÃO DO MATERIAL'),
                            ),
                            SizedBox(
                              width: 140,
                              child: _colHeader(
                                'CUSTO PADRÃO (CPV)',
                                align: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          itemCount: _produtos.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            indent: 24,
                            endIndent: 24,
                          ),
                          itemBuilder: (context, i) {
                            final p = _produtos[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      p.code,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 5,
                                    child: Text(
                                      p.description,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF2D3748),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 140,
                                    child: Text(
                                      p.cpv != null
                                          ? 'R\$ ${p.cpv!.toStringAsFixed(2).replaceAll('.', ',')}'
                                          : 'Não Definido',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: p.cpv != null
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: p.cpv != null
                                            ? const Color(0xFF1A1A1A)
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
                    ],
                  ),
          ),
          if (_produtos.isNotEmpty && !_loadingProdutos)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Text(
                    'Visualizando ${_produtos.length} SKUs no cluster comercial.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required String label,
    required String valor,
    required String sub,
    required MaterialColor cor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cor.shade50.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cor.shade100),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cor.shade100.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: cor.shade800),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.bold,
                      color: cor.shade800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    valor,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: cor.shade900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(fontSize: 11, color: cor.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colHeader(String label, {TextAlign align = TextAlign.left}) {
    return Text(
      label,
      textAlign: align,
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 0.5,
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade500,
      ),
    );
  }

  Widget _vazio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 52,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma hierarquia mapeada no banco',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _TreeTile extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final bool isOpen;
  final VoidCallback onTap;
  final Widget leading;
  final Widget title;
  final Widget trailing;

  const _TreeTile({
    required this.padding,
    required this.isOpen,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Icon(
              isOpen
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_right_rounded,
              size: 18,
              color: Colors.grey.shade400,
            ),
            const SizedBox(width: 4),
            leading,
            const SizedBox(width: 8),
            Expanded(child: title),
            trailing,
          ],
        ),
      ),
    );
  }
}
