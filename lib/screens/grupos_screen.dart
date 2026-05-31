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
    setState(() => _loading = true);
    try {
      final cats = await _service.getHierarchy();
      setState(() {
        _categorias = cats;
        _loading = false;
        if (cats.isNotEmpty) _categoriasAbertas.add(cats.first.id);
      });
    } catch (e) {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? Colors.red : Colors.green,
      ),
    );
  }

  // ── Edição de CPV ──────────────────────────────────────────────────

  Future<void> _abrirEdicaoCpv() async {
    // Mapa local código → controller, inicializado com o CPV atual
    final controllers = {
      for (final p in _produtos)
        p.code: TextEditingController(
          text: p.cpv != null ? p.cpv!.toStringAsFixed(2) : '',
        ),
    };

    final salvo = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogEditarCpv(
        clusterNome: _clusterSelecionado!.name,
        produtos: _produtos,
        controllers: controllers,
      ),
    );

    // Descarta controllers
    for (final c in controllers.values) {
      c.dispose();
    }

    if (salvo != true) return;

    // Salva apenas os que mudaram ou foram preenchidos
    int salvos = 0;
    for (final p in _produtos) {
      final texto = controllers[p.code]?.text.trim() ?? '';
      if (texto.isEmpty) continue;
      final valor = double.tryParse(texto.replaceAll(',', '.'));
      if (valor == null) continue;
      if (valor == p.cpv) continue; // não mudou
      try {
        await _service.upsertCpv(productCode: p.code, costValue: valor);
        salvos++;
      } catch (e) {
        _snack('Erro ao salvar ${p.code}: $e', erro: true);
      }
    }

    if (salvos > 0) {
      _snack('$salvos CPV(s) atualizado(s) com sucesso!');
      // Recarrega produtos do cluster para refletir os novos valores
      await _selecionarCluster(_clusterSelecionado!, _grupoSelecionado!);
    }
  }

  // ── KPIs do cluster ────────────────────────────────────────────────

  double? get _variacaoCpvMedia {
    final comCpv = _produtos.where((p) => p.cpv != null && p.cpv! > 0).toList();
    if (comCpv.isEmpty) return null;
    // Variação = desvio relativo ao CPV médio (placeholder visual)
    final media =
        comCpv.map((p) => p.cpv!).reduce((a, b) => a + b) / comCpv.length;
    final min = comCpv.map((p) => p.cpv!).reduce((a, b) => a < b ? a : b);
    if (media == 0) return null;
    return ((media - min) / media) * 100;
  }

  // ── BUILD ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Column(
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
                        SizedBox(width: 320, child: _arvore()),
                        const SizedBox(width: 20),
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
                const Icon(
                  Icons.account_tree_outlined,
                  size: 16,
                  color: _laranja,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Hierarquia',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '${_categorias.length} categorias',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: _categorias.map(_noCategoria).toList(),
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
          onTap: () => setState(
            () => aberta
                ? _categoriasAbertas.remove(cat.id)
                : _categoriasAbertas.add(cat.id),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                const Icon(Icons.folder_outlined, size: 16, color: _laranja),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cat.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${cat.totalSkus}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
        ),
        if (aberta) ...cat.lines.map((l) => _noLinha(l)),
      ],
    );
  }

  Widget _noLinha(ProductLine linha) {
    final aberta = _linhasAbertas.contains(linha.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(
            () => aberta
                ? _linhasAbertas.remove(linha.id)
                : _linhasAbertas.add(linha.id),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 6, 12, 6),
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
                const Icon(
                  Icons.layers_outlined,
                  size: 14,
                  color: Colors.blueGrey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    linha.name,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${linha.totalSkus}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ],
            ),
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
        InkWell(
          onTap: () => setState(
            () => aberto
                ? _gruposAbertos.remove(grupo.id)
                : _gruposAbertos.add(grupo.id),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(44, 6, 12, 6),
            child: Row(
              children: [
                Icon(
                  aberto
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 15,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.grid_view_outlined,
                  size: 13,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    grupo.name,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${grupo.totalSkus}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ],
            ),
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
      child: Container(
        color: selecionado ? _laranja.withOpacity(0.07) : null,
        padding: const EdgeInsets.fromLTRB(60, 7, 12, 7),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: selecionado ? _laranja : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                cluster.name,
                style: TextStyle(
                  fontSize: 12,
                  color: selecionado ? _laranja : Colors.grey.shade800,
                  fontWeight: selecionado ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${cluster.skuCount}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  // ── PAINEL DIREITO ─────────────────────────────────────────────────

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
                Icons.touch_app_outlined,
                size: 48,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 12),
              Text(
                'Selecione um agrupamento',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Os materiais do cluster aparecerão aqui',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _clusterSelecionado!.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _grupoSelecionado?.name ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Editar CPV'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _laranja,
                    side: const BorderSide(color: _laranja),
                  ),
                  onPressed: _loadingProdutos || _produtos.isEmpty
                      ? null
                      : _abrirEdicaoCpv,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── KPI cards ──
          if (!_loadingProdutos)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _kpiCard(
                    icon: Icons.inventory_2_outlined,
                    label: 'Materiais',
                    valor: '${_produtos.length}',
                    sub: '$comCpv com CPV · $semCpv sem CPV',
                    cor: Colors.blue,
                  ),
                  const SizedBox(width: 12),
                  _kpiCard(
                    icon: Icons.trending_up_outlined,
                    label: 'Variação CPV',
                    valor: variacao != null
                        ? '${variacao.toStringAsFixed(1)}%'
                        : '—',
                    sub: 'Desvio min→média',
                    cor: variacao != null && variacao > 20
                        ? Colors.orange
                        : Colors.green,
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),
          const Divider(height: 1),

          // ── Cabeçalho tabela ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: Colors.grey.shade50,
            child: Row(
              children: [
                Expanded(flex: 2, child: _colHeader('Código')),
                Expanded(flex: 5, child: _colHeader('Descrição')),
                SizedBox(
                  width: 110,
                  child: _colHeader('CPV', align: TextAlign.right),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Lista de produtos ──
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
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = _produtos[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
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
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: Text(
                                p.cpv != null
                                    ? 'R\$ ${p.cpv!.toStringAsFixed(2).replaceAll('.', ',')}'
                                    : '—',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: p.cpv != null
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                  color: p.cpv != null
                                      ? Colors.grey.shade800
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

          if (_produtos.isNotEmpty && !_loadingProdutos)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Text(
                '${_produtos.length} materiais neste agrupamento',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cor.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cor.shade100),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cor.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: cor.shade700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: cor.shade700),
                  ),
                  Text(
                    valor,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: cor.shade800,
                    ),
                  ),
                  Text(
                    sub,
                    style: TextStyle(fontSize: 10, color: cor.shade600),
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
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
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

// ── Dialog de edição de CPV ─────────────────────────────────────────

class _DialogEditarCpv extends StatefulWidget {
  final String clusterNome;
  final List<ClusterProduct> produtos;
  final Map<String, TextEditingController> controllers;

  const _DialogEditarCpv({
    required this.clusterNome,
    required this.produtos,
    required this.controllers,
  });

  @override
  State<_DialogEditarCpv> createState() => _DialogEditarCpvState();
}

class _DialogEditarCpvState extends State<_DialogEditarCpv> {
  static const _laranja = Color(0xFFFF6B00);
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final filtrados = widget.produtos
        .where(
          (p) =>
              _busca.isEmpty ||
              p.description.toLowerCase().contains(_busca.toLowerCase()) ||
              p.code.contains(_busca),
        )
        .toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 620,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, color: _laranja, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Editar CPV',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.clusterNome,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
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

            const SizedBox(height: 12),

            // Busca
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                onChanged: (v) => setState(() => _busca = v),
                decoration: InputDecoration(
                  hintText: 'Buscar material...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Header tabela
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
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
                    width: 130,
                    child: Text(
                      'CPV (R\$)',
                      textAlign: TextAlign.right,
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

            // Lista editável
            Expanded(
              child: filtrados.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhum material encontrado',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: filtrados.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = filtrados[i];
                        final ctrl = widget.controllers[p.code]!;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
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
                                flex: 4,
                                child: Text(
                                  p.description,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(
                                width: 130,
                                child: TextField(
                                  controller: ctrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: InputDecoration(
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
                                    fillColor: Colors.grey.shade50,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                        color: _laranja,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            const Divider(height: 1),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                children: [
                  Text(
                    '${widget.produtos.length} materiais · edite os valores e clique em Salvar',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Salvar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _laranja,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
