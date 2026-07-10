// lib/screens/materials_screen.dart
//
// Tela de Materiais — com painel lateral de hierarquia expansível
//
// Hierarquia: empresa → marca → gramatura → categoria → linha → agrupamento
// Ao clicar num agrupamento, a tabela mostra os materiais daquele agrupamento.
// Materiais sem empresa são ignorados (empresa é o mínimo obrigatório).
// Colunas visíveis: código, descrição, gramatura, CPV, deduções, despesas diversas, status.

import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:pole_price/models/material/material_model.dart';
import 'package:pole_price/service/material/materials_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:html' as html;

// ── Paleta ──────────────────────────────────────────────────────────────────
class _C {
  static const bg           = Color(0xFFF5F6F8);
  static const white        = Color(0xFFFFFFFF);
  static const laranja      = Color(0xFFFF6B00);
  static const laranjaLight = Color(0xFFFFF0E6);
  static const azulEscuro   = Color(0xFF0D1F35);
  static const verde        = Color(0xFF0A7C4E);
  static const verdeLight   = Color(0xFFD4F0E4);
  static const ambar        = Color(0xFFF59E0B);
  static const ambarLight   = Color(0xFFFEF3C7);
  static const cinzaBorda   = Color(0xFFE2E8F0);
  static const cinzaTexto   = Color(0xFF2C2C2C);
  static const cinzaSub     = Color(0xFF64748B);
  static const cinzaFundo   = Color(0xFFF8FAFC);
  static const cinzaSidebar = Color(0xFFEFF2F6);
  static const vermelho     = Color(0xFFDC2626);
  static const vermelhoLight= Color(0xFFFEE2E2);
}

// ── Modelo de nó da árvore ───────────────────────────────────────────────────
class _TreeNode {
  final String label;
  final int nivel; // 0=empresa, 1=marca, 2=gramatura, 3=categoria, 4=linha, 5=agrupamento
  final List<_TreeNode> filhos;
  bool expandido;

  _TreeNode({
    required this.label,
    required this.nivel,
    this.filhos = const [],
    this.expandido = false,
  });
}

// ── Screen ───────────────────────────────────────────────────────────────────
class MaterialsScreen extends StatefulWidget {
  const MaterialsScreen({super.key});

  @override
  State<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends State<MaterialsScreen> {
  late final MaterialsService _service;

  List<MaterialSap> _materiais = [];
  bool _loading = true;
  bool _syncando = false;
  bool _baixando = false;
  bool _uploadando = false;
  bool _uploadandoCustos = false;

  // Seleção na árvore
  String? _agrupamentoSelecionado;
  String? _empresaSelecionada;
  String? _marcaSelecionada;
  String? _gramaturaSelecionada;
  String? _categoriaSelecionada;
  String? _linhaSelecionada;

  // Busca dentro da tabela
  final _buscaCtrl = TextEditingController();

  // Caminho (empresa|marca|gramatura|categoria|linha) a auto-expandir na
  // sidebar quando a busca global encontra um material fora do agrupamento
  // atualmente selecionado.
  List<String>? _caminhoParaExpandir;

  @override
  void initState() {
    super.initState();
    _service = MaterialsService(Supabase.instance.client);
    _carregar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  // ── Carregar ─────────────────────────────────────────────────────────────

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final lista = await _service.listar();
      if (!mounted) return;
      setState(() {
        // filtra fora materiais sem empresa
        _materiais = lista.where((m) => m.empresa != null && m.empresa!.isNotEmpty).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Erro ao carregar materiais: $e', erro: true);
    }
  }

  // ── Busca global (encontra o material em qualquer lugar da hierarquia) ───

  void _selecionarMaterialGlobal(MaterialSap m) {
    final emp = m.empresa ?? '(sem empresa)';
    final mar = m.marca ?? '(sem marca)';
    final gra = m.gramatura?.toString() ?? '(sem gramatura)';
    final cat = m.categoria ?? '(sem categoria)';
    final lin = m.linha ?? '(sem linha)';
    final agr = m.agrupamentoPreco ?? '(sem agrupamento)';

    setState(() {
      _empresaSelecionada = emp;
      _marcaSelecionada = mar;
      _gramaturaSelecionada = gra;
      _categoriaSelecionada = cat;
      _linhaSelecionada = lin;
      _agrupamentoSelecionado = agr;
      _caminhoParaExpandir = [emp, mar, gra, cat, lin];
      _buscaCtrl.clear();
    });
  }

  // ── Materiais exibidos na tabela ─────────────────────────────────────────

  List<MaterialSap> get _materiaisFiltrados {
    if (_agrupamentoSelecionado == null) return [];

    var lista = _materiais.where((m) {
      if (m.empresa != _empresaSelecionada) return false;
      if (_marcaSelecionada != null && m.marca != _marcaSelecionada) return false;
      if (_gramaturaSelecionada != null && (m.gramatura?.toString()) != _gramaturaSelecionada) return false;
      if (_categoriaSelecionada != null && m.categoria != _categoriaSelecionada) return false;
      if (_linhaSelecionada != null && m.linha != _linhaSelecionada) return false;
      if (m.agrupamentoPreco != _agrupamentoSelecionado) return false;
      return true;
    }).toList();

    final busca = _buscaCtrl.text.toLowerCase().trim();
    if (busca.isNotEmpty) {
      lista = lista.where((m) =>
        m.materialCode.toLowerCase().contains(busca) ||
        m.description.toLowerCase().contains(busca)
      ).toList();
    }

    return lista;
  }

  // ── Árvore de hierarquia ─────────────────────────────────────────────────
  // Constrói a estrutura: empresa → marca → gramatura → categoria → linha → agrupamento

  List<_TreeNode> _buildTree() {
    final Map<String, Map<String, Map<String, Map<String, Map<String, Set<String>>>>>> tree = {};

    for (final m in _materiais) {
      final emp = m.empresa ?? '(sem empresa)';
      final mar = m.marca ?? '(sem marca)';
      final gra = m.gramatura?.toString() ?? '(sem gramatura)';
      final cat = m.categoria ?? '(sem categoria)';
      final lin = m.linha ?? '(sem linha)';
      final agr = m.agrupamentoPreco ?? '(sem agrupamento)';

      tree
        .putIfAbsent(emp, () => {})
        .putIfAbsent(mar, () => {})
        .putIfAbsent(gra, () => {})
        .putIfAbsent(cat, () => {})
        .putIfAbsent(lin, () => {})
        .add(agr);
    }

    return tree.entries.map((eEntry) {
      return _TreeNode(
        label: eEntry.key,
        nivel: 0,
        filhos: eEntry.value.entries.map((mEntry) {
          return _TreeNode(
            label: mEntry.key,
            nivel: 1,
            filhos: mEntry.value.entries.map((gEntry) {
              return _TreeNode(
                label: gEntry.key,
                nivel: 2,
                filhos: gEntry.value.entries.map((cEntry) {
                  return _TreeNode(
                    label: cEntry.key,
                    nivel: 3,
                    filhos: cEntry.value.entries.map((lEntry) {
                      return _TreeNode(
                        label: lEntry.key,
                        nivel: 4,
                        filhos: lEntry.value.map((agr) => _TreeNode(
                          label: agr,
                          nivel: 5,
                        )).toList()..sort((a, b) => a.label.compareTo(b.label)),
                      );
                    }).toList()..sort((a, b) => a.label.compareTo(b.label)),
                  );
                }).toList()..sort((a, b) => a.label.compareTo(b.label)),
              );
            }).toList()..sort((a, b) => _compararGramatura(a.label, b.label)),
          );
        }).toList()..sort((a, b) => a.label.compareTo(b.label)),
      );
    }).toList()..sort((a, b) => a.label.compareTo(b.label));
  }

  /// Ordena gramaturas numericamente (100, 200, 1000...) em vez de
  /// alfabeticamente (que colocaria "1000" antes de "200"). Valores não
  /// numéricos (ex: "PESO VARIAVEL") vão para o final, em ordem alfabética.
  static int _compararGramatura(String a, String b) {
    final na = double.tryParse(a.replaceAll(',', '.'));
    final nb = double.tryParse(b.replaceAll(',', '.'));
    if (na != null && nb != null) return na.compareTo(nb);
    if (na != null) return -1;
    if (nb != null) return 1;
    return a.compareTo(b);
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  int get _completos      => _materiais.where((m) => m.status == MaterialStatus.completo).length;
  int get _semCpv         => _materiais.where((m) => m.status == MaterialStatus.semCpv).length;
  int get _semHierarquia  => _materiais.where((m) => m.status == MaterialStatus.semHierarquia).length;

  // ── Sync / Download / Upload ──────────────────────────────────────────────

  Future<void> _syncSap() async {
    setState(() => _syncando = true);
    try {
      final result = await _service.syncSap();
      if (!mounted) return;
      _snack('✓ SAP sincronizado — ${result.totalFromSap} recebidos, ${result.upserted} atualizados em ${result.durationMs}ms');
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      _snack('Erro ao sincronizar SAP: $e', erro: true);
    } finally {
      if (mounted) setState(() => _syncando = false);
    }
  }

  Future<void> _baixarPlanilhaAgrupamento() async {
    if (_materiais.isEmpty) {
      _snack('Sincronize com o SAP primeiro para gerar a planilha.', erro: true);
      return;
    }
    setState(() => _baixando = true);
    try {
      final bytes = await _service.gerarPlanilhaModelo(_materiais);
      if (!mounted) return;
      _downloadWeb(bytes, 'pole_price_agrupamento.xlsx');
      _snack('Planilha de agrupamento baixada — preencha e suba de volta.');
    } catch (e) {
      if (!mounted) return;
      _snack('Erro ao gerar planilha: $e', erro: true);
    } finally {
      if (mounted) setState(() => _baixando = false);
    }
  }

  Future<void> _baixarPlanilhaCustos() async {
    if (_materiais.isEmpty) {
      _snack('Sincronize com o SAP primeiro para gerar a planilha.', erro: true);
      return;
    }
    setState(() => _baixando = true);
    try {
      final bytes = await _service.gerarPlanilhaCustos(_materiais);
      if (!mounted) return;
      _downloadWeb(bytes, 'pole_price_custos.xlsx');
      _snack('Planilha de custos baixada — preencha e suba em "Subir Custos".');
    } catch (e) {
      if (!mounted) return;
      _snack('Erro ao gerar planilha de custos: $e', erro: true);
    } finally {
      if (mounted) setState(() => _baixando = false);
    }
  }

  void _downloadWeb(Uint8List bytes, String filename) {
    final blob = html.Blob(
      [bytes],
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _uploadPlanilha() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) { _snack('Não foi possível ler o arquivo.', erro: true); return; }

    setState(() => _uploadando = true);
    try {
      final res = await _service.processarUpload(bytes);
      if (!mounted) return;
      if (res.erros > 0) {
        _mostrarErrosUpload(res);
      } else {
        _snack('✓ ${res.atualizados} materiais atualizados com sucesso!');
      }
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      _snack('Erro ao processar planilha: $e', erro: true);
    } finally {
      if (mounted) setState(() => _uploadando = false);
    }
  }

  Future<void> _uploadCustos() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) { _snack('Não foi possível ler o arquivo.', erro: true); return; }

    setState(() => _uploadandoCustos = true);
    try {
      final res = await _service.processarUploadCustos(bytes);
      if (!mounted) return;
      if (res.erros > 0) {
        _mostrarErrosUpload(res);
      } else {
        _snack('✓ ${res.atualizados} custos (CPV/Ded/DV) atualizados com sucesso!');
      }
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      _snack('Erro ao processar planilha de custos: $e', erro: true);
    } finally {
      if (mounted) setState(() => _uploadandoCustos = false);
    }
  }

  void _mostrarErrosUpload(UploadResult res) {
    showDialog(
      context: context,
      builder: (_) => _DialogErrosUpload(
        atualizados: res.atualizados,
        erros: res.erros,
        mensagens: res.mensagensErro,
      ),
    );
  }

  // ── Snack ─────────────────────────────────────────────────────────────────

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(erro ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
      ]),
      backgroundColor: erro ? _C.vermelho : _C.verde,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(
        children: [
          _topBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _C.laranja))
                : _materiais.isEmpty
                    ? _estadoVazio()
                    : _corpo(),
          ),
        ],
      ),
    );
  }

  // ── Botão "Baixar Planilha" (menu: Agrupamento ou Custos) ────────────────

  Widget _botaoBaixarPlanilha() {
    final desabilitado = _baixando || _materiais.isEmpty;
    return PopupMenuButton<String>(
      tooltip: 'Baixar planilha',
      enabled: !desabilitado,
      onSelected: (v) {
        if (v == 'agrupamento') {
          _baixarPlanilhaAgrupamento();
        } else {
          _baixarPlanilhaCustos();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'agrupamento',
          child: Text('Planilha de Agrupamento'),
        ),
        PopupMenuItem(
          value: 'custos',
          child: Text('Planilha de Custos'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: desabilitado
                ? _C.cinzaBorda
                : _C.cinzaSub.withOpacity(0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _baixando
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: desabilitado ? _C.cinzaBorda : _C.cinzaSub,
                    ),
                  )
                : Icon(Icons.download_rounded,
                    size: 16,
                    color: desabilitado ? _C.cinzaBorda : _C.cinzaSub),
            const SizedBox(width: 8),
            Text('Baixar Planilha',
                style: TextStyle(
                  fontSize: 13,
                  color: desabilitado ? _C.cinzaBorda : _C.cinzaSub,
                )),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down_rounded,
                size: 18, color: desabilitado ? _C.cinzaBorda : _C.cinzaSub),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _topBar() {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: _C.white,
        border: Border(bottom: BorderSide(color: _C.cinzaBorda)),
      ),
      child: Row(
        children: [
          const Text('Materiais',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _C.azulEscuro)),
          const SizedBox(width: 8),
          if (_materiais.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _C.cinzaFundo,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _C.cinzaBorda),
              ),
              child: Text('${_materiais.length}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _C.cinzaSub)),
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  _BotaoAcao(label: 'Sincronizar SAP', icon: Icons.sync_rounded,
                    loading: _syncando, cor: _C.azulEscuro, onTap: _syncando ? null : _syncSap),
                  const SizedBox(width: 10),
                  _botaoBaixarPlanilha(),
                  const SizedBox(width: 10),
                  _BotaoAcao(label: 'Subir Agrupamento', icon: Icons.upload_rounded,
                    loading: _uploadando, cor: _C.laranja,
                    onTap: (_uploadando || _materiais.isEmpty) ? null : _uploadPlanilha),
                  const SizedBox(width: 10),
                  _BotaoAcao(label: 'Subir Custos', icon: Icons.request_quote_rounded,
                    loading: _uploadandoCustos, cor: _C.laranja,
                    onTap: _uploadandoCustos ? null : _uploadCustos),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Corpo: sidebar + conteúdo ─────────────────────────────────────────────

  Widget _corpo() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Painel lateral de hierarquia ──
        _Sidebar(
          tree: _buildTree(),
          agrupamentoSelecionado: _agrupamentoSelecionado,
          expandirCaminho: _caminhoParaExpandir,
          onAgrupamentoTap: (emp, mar, gra, cat, lin, agr) {
            setState(() {
              _empresaSelecionada    = emp;
              _marcaSelecionada      = mar;
              _gramaturaSelecionada  = gra;
              _categoriaSelecionada  = cat;
              _linhaSelecionada      = lin;
              _agrupamentoSelecionado = agr;
              _buscaCtrl.clear();
            });
          },
        ),

        // ── Área principal ──
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BuscaGlobalMaterial(
                  materiais: _materiais,
                  onSelecionado: _selecionarMaterialGlobal,
                ),
                const SizedBox(height: 16),
                _kpiRow(),
                const SizedBox(height: 20),
                if (_agrupamentoSelecionado != null) ...[
                  _breadcrumb(),
                  const SizedBox(height: 12),
                  _barraBusca(),
                  const SizedBox(height: 12),
                  Expanded(child: _tabela()),
                ] else
                  Expanded(child: _instrucaoSelecionar()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── KPIs ──────────────────────────────────────────────────────────────────

  Widget _kpiRow() {
    return Row(children: [
      _kpi('Total', '${_materiais.length}', Icons.inventory_2_outlined, Colors.blue),
      const SizedBox(width: 12),
      _kpi('Completos', '$_completos', Icons.check_circle_outline_rounded, Colors.green),
      const SizedBox(width: 12),
      _kpi('Sem CPV', '$_semCpv', Icons.attach_money_rounded, Colors.amber),
      const SizedBox(width: 12),
      _kpi('Sem Hierarquia', '$_semHierarquia', Icons.account_tree_outlined, Colors.red),
    ]);
  }

  Widget _kpi(String label, String valor, IconData icon, MaterialColor cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _C.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.cinzaBorda),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: cor.shade50, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: cor.shade700),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(valor, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cor.shade800)),
            Text(label, style: const TextStyle(fontSize: 11, color: _C.cinzaSub, fontWeight: FontWeight.w500)),
          ]),
        ]),
      ),
    );
  }

  // ── Breadcrumb ────────────────────────────────────────────────────────────

  Widget _breadcrumb() {
    final partes = [
      _empresaSelecionada,
      _marcaSelecionada,
      _gramaturaSelecionada,
      _categoriaSelecionada,
      _linhaSelecionada,
      _agrupamentoSelecionado,
    ].whereType<String>().toList();

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        for (int i = 0; i < partes.length; i++) ...[
          if (i > 0)
            const Icon(Icons.chevron_right_rounded, size: 16, color: _C.cinzaSub),
          Text(
            partes[i],
            style: TextStyle(
              fontSize: 12,
              color: i == partes.length - 1 ? _C.laranja : _C.cinzaSub,
              fontWeight: i == partes.length - 1 ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ],
    );
  }

  // ── Barra de busca da tabela ──────────────────────────────────────────────

  Widget _barraBusca() {
    return Row(children: [
      SizedBox(
        width: 300,
        child: TextField(
          controller: _buscaCtrl,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Buscar por código ou descrição...',
            hintStyle: const TextStyle(fontSize: 13, color: _C.cinzaSub),
            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _C.cinzaSub),
            isDense: true,
            filled: true,
            fillColor: _C.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _C.cinzaBorda),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _C.cinzaBorda),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _C.laranja, width: 1.5),
            ),
          ),
        ),
      ),
      const Spacer(),
      Text('${_materiaisFiltrados.length} materiais',
        style: const TextStyle(fontSize: 12, color: _C.cinzaSub)),
    ]);
  }

  // ── Tabela ────────────────────────────────────────────────────────────────

  Widget _tabela() {
    final lista = _materiaisFiltrados;
    return Container(
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.cinzaBorda),
      ),
      child: Column(children: [
        _headerTabela(),
        const Divider(height: 1, color: _C.cinzaBorda),
        Expanded(
          child: lista.isEmpty
              ? _semResultados()
              : ListView.separated(
                  itemCount: lista.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: _C.cinzaBorda),
                  itemBuilder: (_, i) => _linhaTabela(lista[i], i),
                ),
        ),
      ]),
    );
  }

  Widget _headerTabela() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: _C.cinzaFundo,
      child: Row(children: [
        _th('CÓDIGO',            flex: 2),
        _th('DESCRIÇÃO',         flex: 5),
        _th('GRAMATURA',         flex: 2),
        _th('CPV (R\$)',         flex: 2, align: TextAlign.right),
        _th('DEDUÇÕES',          flex: 2, align: TextAlign.right),
        _th('DESP. VAR.',         flex: 2, align: TextAlign.right),
        _th('VÍNCULO',           flex: 2, align: TextAlign.center),
        _th('STATUS',            flex: 2, align: TextAlign.center),
      ]),
    );
  }

  Widget _th(String label, {int flex = 1, TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(label, textAlign: align,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _C.cinzaSub, letterSpacing: 0.5)),
    );
  }

  Widget _linhaTabela(MaterialSap m, int index) {
    return Container(
      color: index.isEven ? _C.white : _C.cinzaFundo,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        // Código
        Expanded(flex: 2, child: Text(m.materialCode,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _C.cinzaSub, fontFamily: 'monospace'))),

        // Descrição
        Expanded(flex: 5, child: Text(m.description,
          style: const TextStyle(fontSize: 13, color: _C.cinzaTexto), overflow: TextOverflow.ellipsis)),

        // Gramatura
        Expanded(flex: 2, child: _valorOuTraco(
          m.gramatura != null ? '${m.gramatura} g/m²' : null)),

        // CPV
        Expanded(flex: 2, child: Text(
          m.cpvReais != null
              ? 'R\$ ${m.cpvReais!.toStringAsFixed(2).replaceAll('.', ',')}'
              : '—',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 12,
            fontWeight: m.cpvReais != null ? FontWeight.w600 : FontWeight.normal,
            color: m.cpvReais != null ? _C.cinzaTexto : Colors.grey.shade400,
          ),
        )),

        // Deduções
        Expanded(flex: 2, child: Text(
          m.deducoesPct != null ? '${(m.deducoesPct! * 100).toStringAsFixed(1)}%' : '—',
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 12, color: m.deducoesPct != null ? _C.cinzaTexto : Colors.grey.shade400),
        )),

        // Despesas variáveis
        Expanded(flex: 2, child: Text(
          m.despesasVarPct != null ? '${(m.despesasVarPct! * 100).toStringAsFixed(1)}%' : '—',
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 12, color: m.despesasVarPct != null ? _C.cinzaTexto : Colors.grey.shade400),
        )),

        // Vínculo de preço (pai/filho do agrupamento)
        Expanded(flex: 2, child: Center(child: _vinculoAcao(m))),

        // Status badge
        Expanded(flex: 2, child: Center(child: _badgeStatus(m.status))),
      ]),
    );
  }

  // ── Vínculo de preço (pai/filho dentro do agrupamento) ────────────────────

  Widget _vinculoAcao(MaterialSap m) {
    if (m.agrupamentoPreco == null) {
      return IconButton(
        icon: Icon(Icons.link_off, size: 16, color: Colors.grey.shade300),
        tooltip: 'Defina o agrupamento antes de vincular o preço',
        onPressed: null,
      );
    }
    final excecaoLabel = m.excecaoPrecoPct != null
        ? '${m.excecaoPrecoPct! >= 0 ? '+' : ''}${(m.excecaoPrecoPct! * 100).toStringAsFixed(1)}%'
        : '';
    return Tooltip(
      message: m.materialPaiCode != null
          ? 'Segue ${m.materialPaiCode} $excecaoLabel'
          : 'Definir vínculo de preço',
      child: IconButton(
        icon: Icon(
          m.materialPaiCode != null ? Icons.link : Icons.add_link,
          size: 18,
          color: m.materialPaiCode != null ? _C.laranja : _C.cinzaSub,
        ),
        onPressed: () => _abrirVinculoDialog(m),
      ),
    );
  }

  Future<void> _abrirVinculoDialog(MaterialSap m) async {
    final irmaos = _materiais
        .where((o) =>
            o.materialCode != m.materialCode &&
            o.empresa == m.empresa &&
            o.marca == m.marca &&
            o.gramatura == m.gramatura &&
            o.categoria == m.categoria &&
            o.linha == m.linha &&
            o.agrupamentoPreco == m.agrupamentoPreco &&
            o.materialPaiCode == null) // evita chains (pai não pode ser filho)
        .toList();

    String? paiSelecionado = m.materialPaiCode;
    final excecaoCtrl = TextEditingController(
      text: m.excecaoPrecoPct != null
          ? (m.excecaoPrecoPct! * 100).toStringAsFixed(1)
          : '',
    );

    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Vínculo de preço — ${m.materialCode}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Agrupamento: ${m.agrupamentoPreco}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  value: paiSelecionado,
                  decoration: const InputDecoration(
                    labelText: 'Material pai',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Nenhum (remover vínculo)'),
                    ),
                    ...irmaos.map(
                      (o) => DropdownMenuItem<String?>(
                        value: o.materialCode,
                        child: Text(
                          '${o.materialCode} — ${o.description}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => paiSelecionado = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: excecaoCtrl,
                  enabled: paiSelecionado != null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '% Exceção em relação ao pai',
                    hintText: 'ex: 10 para +10%, -5 para -5%',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (resultado != true) return;

    final excecaoVal = paiSelecionado != null
        ? double.tryParse(excecaoCtrl.text.replaceAll(',', '.'))
        : null;

    try {
      await _service.salvarVinculoPreco(
        materialCode: m.materialCode,
        paiCode: paiSelecionado,
        excecaoPct: excecaoVal != null ? excecaoVal / 100 : null,
      );
      await _carregar();
      _snack('Vínculo de preço atualizado.');
    } catch (e) {
      _snack('Erro ao salvar vínculo: $e', erro: true);
    }
  }

  Widget _valorOuTraco(String? valor) {
    if (valor != null) {
      return Text(valor, style: const TextStyle(fontSize: 12, color: _C.cinzaTexto));
    }
    return Text('—', style: TextStyle(fontSize: 12, color: Colors.grey.shade400));
  }

  Widget _badgeStatus(MaterialStatus status) {
    final (label, bg, fg) = switch (status) {
      MaterialStatus.completo      => ('Completo',       _C.verdeLight,   _C.verde),
      MaterialStatus.semCpv        => ('Sem CPV',        _C.ambarLight,   _C.ambar),
      MaterialStatus.semHierarquia => ('Sem Hierarquia', _C.vermelhoLight, _C.vermelho),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _semResultados() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text('Nenhum material encontrado.',
        style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
    ]));
  }

  // ── Instrução inicial ─────────────────────────────────────────────────────

  Widget _instrucaoSelecionar() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _C.laranjaLight, shape: BoxShape.circle),
        child: const Icon(Icons.account_tree_outlined, size: 40, color: _C.laranja),
      ),
      const SizedBox(height: 20),
      const Text('Selecione um agrupamento',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _C.azulEscuro)),
      const SizedBox(height: 8),
      Text('Use o painel à esquerda para navegar pela hierarquia\ne clique em um agrupamento para ver os materiais.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
    ]));
  }

  // ── Estado vazio (sem materiais sincronizados) ────────────────────────────

  Widget _estadoVazio() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: _C.laranjaLight, shape: BoxShape.circle),
        child: const Icon(Icons.inventory_2_outlined, size: 48, color: _C.laranja),
      ),
      const SizedBox(height: 24),
      const Text('Nenhum material cadastrado',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _C.azulEscuro)),
      const SizedBox(height: 8),
      const Text('Clique em "Sincronizar SAP" para importar os materiais.',
        style: TextStyle(fontSize: 14, color: _C.cinzaSub)),
      const SizedBox(height: 32),
      _BotaoAcao(label: 'Sincronizar SAP', icon: Icons.sync_rounded,
        loading: _syncando, cor: _C.azulEscuro, onTap: _syncando ? null : _syncSap, grande: true),
    ]));
  }
}

// ── Busca global de material (sugestões enquanto digita) ─────────────────────
// Ao selecionar uma sugestão, avisa a tela para expandir a hierarquia e
// selecionar o agrupamento do material encontrado.

class _BuscaGlobalMaterial extends StatefulWidget {
  final List<MaterialSap> materiais;
  final void Function(MaterialSap) onSelecionado;

  const _BuscaGlobalMaterial({
    required this.materiais,
    required this.onSelecionado,
  });

  @override
  State<_BuscaGlobalMaterial> createState() => _BuscaGlobalMaterialState();
}

class _BuscaGlobalMaterialState extends State<_BuscaGlobalMaterial> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<MaterialSap> _sugestoes = [];

  static const _largura = 380.0;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _removerOverlay();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      // Pequeno atraso pra deixar o tap na sugestão registrar antes de fechar.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_focusNode.hasFocus) _removerOverlay();
      });
    }
  }

  void _onChanged(String texto) {
    final q = texto.trim().toLowerCase();
    setState(() {
      _sugestoes = q.isEmpty
          ? []
          : widget.materiais
              .where((m) =>
                  m.materialCode.toLowerCase().contains(q) ||
                  m.description.toLowerCase().contains(q))
              .take(20)
              .toList();
    });
    if (_sugestoes.isNotEmpty) {
      _mostrarOverlay();
    } else {
      _removerOverlay();
    }
  }

  void _mostrarOverlay() {
    _removerOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: _largura,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 44),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: _sugestoes.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: _C.cinzaBorda),
                itemBuilder: (_, i) {
                  final m = _sugestoes[i];
                  return InkWell(
                    onTap: () => _selecionar(m),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.materialCode,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: _C.cinzaSub,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  m.description,
                                  style: const TextStyle(
                                      fontSize: 13, color: _C.cinzaTexto),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (m.agrupamentoPreco != null)
                                  Text(
                                    m.agrupamentoPreco!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _C.laranja,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const Icon(Icons.north_west_rounded,
                              size: 14, color: _C.cinzaSub),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _removerOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selecionar(MaterialSap m) {
    _removerOverlay();
    _ctrl.clear();
    setState(() => _sugestoes = []);
    _focusNode.unfocus();
    widget.onSelecionado(m);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        width: _largura,
        child: TextField(
          controller: _ctrl,
          focusNode: _focusNode,
          onChanged: _onChanged,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Buscar material por código ou descrição...',
            hintStyle: const TextStyle(fontSize: 13, color: _C.cinzaSub),
            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _C.cinzaSub),
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16, color: _C.cinzaSub),
                    onPressed: () {
                      _ctrl.clear();
                      _onChanged('');
                    },
                  ),
            isDense: true,
            filled: true,
            fillColor: _C.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _C.cinzaBorda),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _C.cinzaBorda),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _C.laranja, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Painel lateral de hierarquia ─────────────────────────────────────────────

class _Sidebar extends StatefulWidget {
  final List<_TreeNode> tree;
  final String? agrupamentoSelecionado;
  // Caminho (empresa, marca, gramatura, categoria, linha) a auto-expandir —
  // usado pela busca global para revelar onde um material está na árvore.
  final List<String>? expandirCaminho;
  final void Function(
    String empresa,
    String? marca,
    String? gramatura,
    String? categoria,
    String? linha,
    String agrupamento,
  ) onAgrupamentoTap;

  const _Sidebar({
    required this.tree,
    required this.agrupamentoSelecionado,
    required this.onAgrupamentoTap,
    this.expandirCaminho,
  });

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  // Estado de expansão por caminho único: "empresa|marca|gramatura|..."
  final Set<String> _expandidos = {};

  // Contexto atual da navegação para montar o caminho
  final Map<String, String> _ctx = {};

  @override
  void initState() {
    super.initState();
    _expandirPrefixos(widget.expandirCaminho);
  }

  @override
  void didUpdateWidget(covariant _Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expandirCaminho != null &&
        !listEquals(widget.expandirCaminho, oldWidget.expandirCaminho)) {
      setState(() => _expandirPrefixos(widget.expandirCaminho));
    }
  }

  void _expandirPrefixos(List<String>? caminho) {
    if (caminho == null) return;
    var acumulado = '';
    for (final parte in caminho) {
      acumulado = acumulado.isEmpty ? parte : '$acumulado|$parte';
      _expandidos.add(acumulado);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: _C.cinzaSidebar,
        border: Border(right: BorderSide(color: _C.cinzaBorda)),
      ),
      child: Column(children: [
        // Cabeçalho
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _C.cinzaBorda)),
            color: _C.white,
          ),
          child: Row(children: [
            const Icon(Icons.account_tree_outlined, size: 16, color: _C.cinzaSub),
            const SizedBox(width: 8),
            const Text('Hierarquia',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _C.azulEscuro)),
            const Spacer(),
            if (_expandidos.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => _expandidos.clear()),
                child: const Text('Recolher', style: TextStyle(fontSize: 11, color: _C.cinzaSub)),
              ),
          ]),
        ),
        // Árvore
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: widget.tree.map((n) => _buildNo(n, '', 0)).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildNo(_TreeNode node, String caminhoAcima, int profundidade) {
    final caminho = caminhoAcima.isEmpty ? node.label : '$caminhoAcima|${node.label}';
    final expandido = _expandidos.contains(caminho);
    final ehFolha = node.nivel == 5; // agrupamento

    // Ícone por nível
    final icone = _iconeNivel(node.nivel);
    final indentLeft = 12.0 + profundidade * 14.0;

    if (ehFolha) {
      final selecionado = widget.agrupamentoSelecionado == node.label;
      return _NoFolha(
        label: node.label,
        icon: icone,
        indentLeft: indentLeft,
        selecionado: selecionado,
        onTap: () {
          // Extrai empresa/marca/gramatura/categoria/linha do caminho
          final partes = caminho.split('|');
          widget.onAgrupamentoTap(
            partes.length > 0 ? partes[0] : '',
            partes.length > 1 ? partes[1] : null,
            partes.length > 2 ? partes[2] : null,
            partes.length > 3 ? partes[3] : null,
            partes.length > 4 ? partes[4] : null,
            node.label,
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nó expansível
        InkWell(
          onTap: () => setState(() {
            if (expandido) {
              _expandidos.remove(caminho);
            } else {
              _expandidos.add(caminho);
            }
          }),
          child: Container(
            padding: EdgeInsets.only(left: indentLeft, right: 12, top: 7, bottom: 7),
            child: Row(children: [
              Icon(icone, size: 14, color: _corNivel(node.nivel)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(node.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: profundidade == 0 ? FontWeight.w700 : FontWeight.w500,
                    color: _C.cinzaTexto,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Contador de folhas
              Text(
                '${_contarFolhas(node)}',
                style: const TextStyle(fontSize: 10, color: _C.cinzaSub),
              ),
              const SizedBox(width: 4),
              Icon(
                expandido ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                size: 16, color: _C.cinzaSub,
              ),
            ]),
          ),
        ),
        if (expandido)
          ...node.filhos.map((f) => _buildNo(f, caminho, profundidade + 1)),
      ],
    );
  }

  int _contarFolhas(_TreeNode node) {
    if (node.nivel == 5) return 1;
    return node.filhos.fold(0, (acc, f) => acc + _contarFolhas(f));
  }

  IconData _iconeNivel(int nivel) {
    return switch (nivel) {
      0 => Icons.business_outlined,
      1 => Icons.local_offer_outlined,
      2 => Icons.straighten_outlined,
      3 => Icons.category_outlined,
      4 => Icons.view_list_outlined,
      5 => Icons.folder_outlined,
      _ => Icons.circle_outlined,
    };
  }

  Color _corNivel(int nivel) {
    return switch (nivel) {
      0 => _C.azulEscuro,
      1 => _C.laranja,
      2 => const Color(0xFF7C3AED),
      3 => const Color(0xFF0891B2),
      4 => const Color(0xFF059669),
      _ => _C.cinzaSub,
    };
  }
}

// ── Nó folha (agrupamento selecionável) ──────────────────────────────────────

class _NoFolha extends StatelessWidget {
  final String label;
  final IconData icon;
  final double indentLeft;
  final bool selecionado;
  final VoidCallback onTap;

  const _NoFolha({
    required this.label,
    required this.icon,
    required this.indentLeft,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: EdgeInsets.only(left: indentLeft - 8, right: 12, top: 7, bottom: 7),
        decoration: BoxDecoration(
          color: selecionado ? _C.laranjaLight : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: selecionado ? Border.all(color: _C.laranja.withOpacity(0.4)) : null,
        ),
        child: Row(children: [
          Icon(icon, size: 14, color: selecionado ? _C.laranja : _C.cinzaSub),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
              style: TextStyle(
                fontSize: 12,
                color: selecionado ? _C.laranja : _C.cinzaTexto,
                fontWeight: selecionado ? FontWeight.w700 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (selecionado)
            Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(color: _C.laranja, shape: BoxShape.circle),
            ),
        ]),
      ),
    );
  }
}

// ── Botão de ação reutilizável ────────────────────────────────────────────────

class _BotaoAcao extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final Color cor;
  final VoidCallback? onTap;
  final bool outlined;
  final bool grande;

  const _BotaoAcao({
    required this.label,
    required this.icon,
    required this.loading,
    required this.cor,
    required this.onTap,
    this.outlined = false,
    this.grande = false,
  });

  @override
  Widget build(BuildContext context) {
    final pad = grande
        ? const EdgeInsets.symmetric(horizontal: 28, vertical: 16)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 10);

    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: loading
            ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cor))
            : Icon(icon, size: 16, color: cor),
        label: Text(label, style: TextStyle(fontSize: 13, color: cor)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: cor.withOpacity(0.4)),
          padding: pad,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: onTap,
      icon: loading
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: FilledButton.styleFrom(
        backgroundColor: cor,
        foregroundColor: Colors.white,
        padding: pad,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// ── Dialog erros de upload ────────────────────────────────────────────────────

class _DialogErrosUpload extends StatelessWidget {
  final int atualizados;
  final int erros;
  final List<String> mensagens;

  const _DialogErrosUpload({
    required this.atualizados,
    required this.erros,
    required this.mensagens,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _C.ambarLight, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.warning_amber_rounded, color: _C.ambar, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Upload concluído com avisos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _C.azulEscuro)),
                Text('$atualizados atualizados · $erros com erro',
                  style: const TextStyle(fontSize: 13, color: _C.cinzaSub)),
              ])),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: _C.cinzaSub),
              ),
            ]),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: mensagens.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 14, color: _C.vermelho),
                  const SizedBox(width: 8),
                  Expanded(child: Text(mensagens[i],
                    style: const TextStyle(fontSize: 12, color: _C.cinzaTexto))),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: _C.azulEscuro,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Fechar'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}