// lib/widgets/app_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pole_price/controllers/permissao_controller.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/screens/home_screen.dart';
import 'package:pole_price/screens/material/materials_screen.dart';
import 'package:pole_price/screens/preco_screen.dart';
import 'package:pole_price/screens/grupos_screen.dart';
import 'package:pole_price/screens/definir_aprovacoes_screen.dart';
import 'package:pole_price/screens/rascunhos_screen.dart';
import 'package:pole_price/screens/historico_screen.dart';
import 'package:pole_price/screens/politicas_screen.dart';
import 'package:pole_price/screens/relatorio_screen.dart';
import 'package:pole_price/screens/config_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pole_price/widgets/lista_picker.dart';
import 'package:pole_price/widgets/grupo_picker.dart';

enum AppPage {
  home,
  precos,
  grupos,
  rascunhos,
  aprovacoes,
  historico,
  politicas,
  relatorio,
  config;

  String get label => switch (this) {
    AppPage.home => 'Home',
    AppPage.precos => 'Preços',
    AppPage.grupos => 'Grupos',
    AppPage.rascunhos => 'Meus Rascunhos',
    AppPage.aprovacoes => 'Aprovações',
    AppPage.historico => 'Histórico',
    AppPage.politicas => 'Políticas',
    AppPage.relatorio => 'Relatório',
    AppPage.config => 'Configurações',
  };

  IconData get icon => switch (this) {
    AppPage.home => Icons.home_rounded,
    AppPage.precos => Icons.attach_money_rounded,
    AppPage.grupos => Icons.account_tree_rounded,
    AppPage.rascunhos => Icons.folder_outlined,
    AppPage.aprovacoes => Icons.check_circle_rounded,
    AppPage.historico => Icons.history_rounded,
    AppPage.politicas => Icons.policy_rounded,
    AppPage.relatorio => Icons.bar_chart_rounded,
    AppPage.config => Icons.settings_rounded,
  };

  bool podeVer(PermissaoController p) => switch (this) {
    AppPage.home => true,
    AppPage.precos => p.podeVerPrecos,
    AppPage.grupos => p.podeVerGrupos,
    AppPage.rascunhos => p.podeVerRascunhos,
    AppPage.aprovacoes => p.podeVerAprovacoes,
    AppPage.historico => p.podeVerHistorico,
    AppPage.politicas => p.podeVerPoliticas,
    AppPage.relatorio => p.podeVerRelatorio,
    AppPage.config => p.podeVerConfig,
  };
}

class _AppShellScope extends InheritedWidget {
  final _AppShellState state;
  const _AppShellScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_AppShellScope old) => false;
}

class AppShell extends StatefulWidget {
  final AppPage initialPage;
  const AppShell({super.key, this.initialPage = AppPage.home});

  static _AppShellState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_AppShellScope>();
    assert(scope != null, 'AppShell.of() chamado fora de um AppShell');
    return scope!.state;
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String? _draftIdInicial;
  late AppPage _paginaAtiva;

  // Parâmetros da PrecoScreen — definidos após o diálogo de modo
  _PrecoParams? _precoParams;

  @override
  void initState() {
    super.initState();
    _paginaAtiva = widget.initialPage;
  }

  void goTo(AppPage page, {String? draftId}) {
    if (page == AppPage.precos) {
      if (draftId != null) {
        _goToPrecosComRascunho(draftId); // ← novo caminho
      } else {
        goToPrecos();
      }
      return;
    }
    // Ao tentar ir para aprovações após salvar um draft pending:
    // só deixa se tiver permissão (admin ou aprovador), senão volta p/ preços do zero.
    if (page == AppPage.aprovacoes && draftId != null) {
      final perm = PermissaoController.instance;
      if (!perm.podeAprovar) {
        // Sem permissão de aprovação: limpa sessão e vai para rascunhos (se puder) ou home
        PrecoController.instance.iniciarNovaSessao();
        setState(() {
          _paginaAtiva = perm.podeVerRascunhos
              ? AppPage.rascunhos
              : AppPage.home;
          _draftIdInicial = null;
          _precoParams = null;
        });
        return;
      }
    }
    if (_paginaAtiva == page && draftId == null) return;
    setState(() {
      _paginaAtiva = page;
      _draftIdInicial = draftId;
    });
  }

  Future<void> _goToPrecosComRascunho(String draftId) async {
    final ctrl = PrecoController.instance;

    // Busca cabeçalho do draft (sem 'modo' — não existe nessa tabela)
    final draft = await Supabase.instance.client
        .from('price_drafts')
        .select('master_list_id') // só isso
        .eq('id', draftId)
        .single();

    // Busca modo e kdgrp do primeiro item
    final primeiroItem = await Supabase.instance.client
        .from('price_draft_items')
        .select('modo, kdgrp')
        .eq('draft_id', draftId)
        .limit(1)
        .maybeSingle();

    final pltyp = draft['master_list_id']?.toString();
    final modoStr = primeiroItem?['modo']?.toString();
    final kdgrp = primeiroItem?['kdgrp']?.toString();

    await ctrl.init();

    ctrl.modo = modoStr == 'grupo' ? SapModo.grupo : SapModo.lista;
    ctrl.pltyp = pltyp;
    ctrl.kdgrp = kdgrp;
    ctrl.selecionada = ctrl.listas.where((l) => l.id == pltyp).firstOrNull;
    ctrl.materiais = [];
    ctrl.filtrados = [];
    ctrl.erro = null;

    if (!mounted) return;

    setState(() {
      _draftIdInicial = draftId;
      _precoParams = _PrecoParams(
        modo: modoStr == 'grupo' ? SapModo.grupo : SapModo.lista,
        pltyp: pltyp ?? '',
        kdgrp: kdgrp,
        datab: null,
        datbi: null,
        databOp: null,
        datbiOp: null,
      );
      _paginaAtiva = AppPage.precos;
    });
  }

  Future<void> goToPrecos() async {
    // Garante que controller.listas está populado antes de abrir o diálogo
    final ctrl = PrecoController.instance;
    await ctrl
        .init(); // já tem guard "if (listas.isNotEmpty) return", seguro chamar

    final params = await showDialog<_PrecoParams>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _ModoPrecoDialog(),
    );
    if (params == null || !mounted) return;

    ctrl.pltyp = null;
    ctrl.kdgrp = null;
    ctrl.datab = null;
    ctrl.datbi = null;
    ctrl.databOp = null;
    ctrl.datbiOp = null;
    ctrl.modo = SapModo.lista;

    ctrl.modo = params.modo;
    ctrl.pltyp = params.pltyp;
    ctrl.kdgrp = params.kdgrp;
    ctrl.datab = params.datab;
    ctrl.datbi = params.datbi;
    ctrl.databOp = params.databOp;
    ctrl.datbiOp = params.datbiOp;

    // ← ISSO resolve o botão esmaecido e o seletor vazio
    ctrl.selecionada = ctrl.listas
        .where((l) => l.id == params.pltyp)
        .firstOrNull;

    ctrl.materiais = [];
    ctrl.filtrados = [];
    ctrl.erro = null;

    setState(() {
      _precoParams = params;
      _paginaAtiva = AppPage.precos;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _AppShellScope(
      state: this,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        body: Row(
          children: [
            _AppSidebar(paginaAtiva: _paginaAtiva, onSelect: goTo),
            Expanded(child: _buildPage(_paginaAtiva)),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(AppPage page) {
    return switch (page) {
      AppPage.home => const HomeScreen(),
      AppPage.precos =>
        _precoParams != null
            ? PrecoScreen(
                key: ValueKey(
                  _draftIdInicial ??
                      '${_precoParams!.pltyp}_'
                          '${_precoParams!.kdgrp}_'
                          '${_precoParams!.datab?.millisecondsSinceEpoch}',
                ),
                draftId: _draftIdInicial, // ← passar aqui
              )
            : const SizedBox.shrink(),
      AppPage.grupos => const MaterialsScreen(),
      AppPage.rascunhos => const RascunhosScreen(),
      AppPage.aprovacoes => AprovacoesScreen(draftIdInicial: _draftIdInicial),
      AppPage.historico => const HistoricoScreen(),
      AppPage.politicas => const PoliticasScreen(),
      AppPage.relatorio => const RelatorioScreen(),
      AppPage.config => const ConfigScreen(),
    };
  }
}

class _AppSidebar extends StatefulWidget {
  final AppPage paginaAtiva;
  final void Function(AppPage) onSelect;
  const _AppSidebar({required this.paginaAtiva, required this.onSelect});

  @override
  State<_AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<_AppSidebar> {
  bool _recolhida = false;

  static const _laranjaFundo = Color(0xFFFF6B00);
  static const _brancoPuro = Colors.white;
  static final _brancoOpaco = Colors.white.withOpacity(0.70);
  static final _brancoHover = Colors.white.withOpacity(0.08);

  static const _mainPages = [
    AppPage.home,
    AppPage.precos,
    AppPage.grupos,
    AppPage.rascunhos,
    AppPage.aprovacoes,
    AppPage.historico,
    AppPage.politicas,
    AppPage.relatorio,
  ];

  @override
  Widget build(BuildContext context) {
    final permCtrl = PermissaoController.instance;
    final double largura = _recolhida ? 72 : 240;

    final paginasVisiveis = _mainPages
        .where((p) => p.podeVer(permCtrl))
        .toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      width: largura,
      decoration: const BoxDecoration(
        color: _laranjaFundo,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 16,
            offset: Offset(4, 0),
          ),
        ],
      ),
      child: OverflowBox(
        maxWidth: largura,
        minWidth: largura,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: largura,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header (Logo) ─────────────────────────────────────────
              SizedBox(
                height: 80,
                width: largura,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _recolhida
                      ? Center(
                          child: IconButton(
                            icon: const Icon(Icons.menu, color: _brancoPuro),
                            onPressed: () => setState(() => _recolhida = false),
                            tooltip: 'Expandir menu',
                          ),
                        )
                      : Row(
                          children: [
                            const SizedBox(width: 8),
                            Expanded(
                              child: Image.asset(
                                'assets/logo_branca.png',
                                height: 200,
                                alignment: Alignment.centerLeft,

                                errorBuilder: (_, __, ___) => const Text(
                                  'Pole Price',
                                  style: TextStyle(
                                    fontWeight: FontWeight
                                        .w800, // Força o bold geométrico da Poppins
                                    fontSize: 16,
                                    color: _brancoPuro,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.menu_open,
                                color: _brancoPuro,
                              ),
                              onPressed: () =>
                                  setState(() => _recolhida = true),
                              tooltip: 'Recolher menu',
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 8),

              // ── Itens Principais do Menu ──────────────────────────────
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  children: paginasVisiveis.map((page) => _item(page)).toList(),
                ),
              ),

              // ── Configurações (Fixo embaixo se for Admin) ──────────────
              if (AppPage.config.podeVer(permCtrl)) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Divider(
                    height: 1,
                    color: Colors.white.withOpacity(0.15),
                  ),
                ),
                _item(AppPage.config),
                const SizedBox(height: 8),
              ],

              // ── Rodapé com a versão ────────────────────────────────────
              if (!_recolhida)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20, left: 24),
                  child: Text(
                    'Versão 1.0.0',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight
                          .w400, // Ajuste sutil para a Poppins pequena
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ),
              if (_recolhida) const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(AppPage page) {
    final ativo = widget.paginaAtiva == page;

    return Tooltip(
      message: _recolhida ? page.label : '',
      preferBelow: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Material(
          color: ativo ? _brancoPuro : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          elevation: ativo ? 2 : 0,
          shadowColor: Colors.black.withOpacity(0.1),
          child: InkWell(
            onTap: () => widget.onSelect(page),
            borderRadius: BorderRadius.circular(24),
            hoverColor: _brancoHover,
            splashColor: _brancoHover,
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _recolhida ? 0 : 16),
                child: _recolhida
                    ? Center(
                        child: Icon(
                          page.icon,
                          size: 24,
                          color: ativo ? _laranjaFundo : _brancoOpaco,
                        ),
                      )
                    : Row(
                        children: [
                          Icon(
                            page.icon,
                            size: 22,
                            color: ativo ? _laranjaFundo : _brancoOpaco,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              page.label,
                              style: TextStyle(
                                fontSize: 14,
                                letterSpacing: 0.2,
                                // Poppins SemiBold no item ativo e Medium no inativo para máxima legibilidade
                                fontWeight: ativo
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: ativo ? _laranjaFundo : _brancoOpaco,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// Modelo interno de parâmetros de navegação para PrecoScreen
// ─────────────────────────────────────────────────────────────────────────────

class _PrecoParams {
  final SapModo modo;
  final String pltyp;
  final String? kdgrp;
  final DateTime? datab;
  final DateTime? datbi;
  final String? databOp;
  final String? datbiOp;

  const _PrecoParams({
    required this.modo,
    required this.pltyp,
    this.kdgrp,
    this.datab,
    this.datbi,
    this.databOp,
    this.datbiOp,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo de seleção de modo SAP (Lista vs Lista+Grupo)
// ─────────────────────────────────────────────────────────────────────────────

class _ModoPrecoDialog extends StatefulWidget {
  const _ModoPrecoDialog();

  @override
  State<_ModoPrecoDialog> createState() => _ModoPrecoDialogState();
}

class _ModoPrecoDialogState extends State<_ModoPrecoDialog> {
  static const _corLaranja = Color(0xFFFF6B00);
  static const _corTexto = Color(0xFF0F172A);
  static const _corSubtexto = Color(0xFF64748B);
  static const _corBorda = Color(0xFFE2E8F0);

  SapModo _modo = SapModo.lista;

  // Listas e grupos vindos do Supabase (catálogo)
  List<Map<String, dynamic>> _listas = [];
  List<Map<String, dynamic>> _grupos = [];
  bool _carregando = true;

  String? _pltypSelecionado;
  String? _kdgrpSelecionado;
  DateFilter _datab = DateFilter(op: DateOp.lte, date: DateTime.now());
  DateFilter _datbi = DateFilter(op: DateOp.gte, date: DateTime.now());

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _carregarCatalogo();
  }

  Future<void> _carregarCatalogo() async {
    try {
      final listas = await _supabase
          .from('price_lists')
          .select('pltyp, ptext')
          .order('ptext');
      final grupos = await _supabase
          .from('price_groups')
          .select('kdgrp, ktext')
          .order('ktext');
      if (mounted) {
        setState(() {
          _listas = List<Map<String, dynamic>>.from(listas);
          _grupos = List<Map<String, dynamic>>.from(grupos);
          _carregando = false;
        });
      }
    } catch (e) {
      debugPrint('_ModoPrecoDialog._carregarCatalogo: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  bool get _podeConfirmar {
    if (_pltypSelecionado == null) return false;
    if (_modo == SapModo.grupo && _kdgrpSelecionado == null) return false;
    return true;
  }

  Future<void> _selecionarData({required bool isInicio}) async {
    final result = await showDialog<DateFilter>(
      context: context,
      builder: (_) => DateFilterDialog(
        initial: isInicio ? _datab : _datbi,
        label: isInicio ? 'Data início (datab)' : 'Data fim (datbi)',
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (isInicio) {
        _datab = result;
      } else {
        _datbi = result;
      }
    });
  }

  String _formatarData(DateFilter? f) {
    if (f == null) return 'Aberto';
    final dt = f.date;
    return '${f.op.label}  ${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Cabeçalho ──
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _corLaranja.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: _corLaranja,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configurar Consulta SAP',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _corTexto,
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Defina o modo, lista e período da consulta',
                          style: TextStyle(
                            fontSize: 11,
                            color: _corSubtexto,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _corSubtexto,
                      size: 18,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      hoverColor: const Color(0xFFF1F5F9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Seleção de modo ──
              const Text(
                'MODO DE CONSULTA',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _corSubtexto,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _modoCard(
                    modo: SapModo.lista,
                    titulo: 'Lista',
                    subtitulo: 'Preços por tabela de preço SAP',
                    icon: Icons.list_alt_rounded,
                  ),
                  const SizedBox(width: 12),
                  _modoCard(
                    modo: SapModo.grupo,
                    titulo: 'Lista + Grupo',
                    subtitulo: 'Preços por grupo de clientes',
                    icon: Icons.account_tree_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Seletor de lista ──
              _label('LISTA DE PREÇO (pltyp)'),
              const SizedBox(height: 8),
              _carregando
                  ? const _LoadingField()
                  : _pickerButton(
                      hint: 'Selecione a lista',
                      value: _pltypSelecionado != null
                          ? '$_pltypSelecionado  —  ${_listas.firstWhere((l) => l["pltyp"] == _pltypSelecionado, orElse: () => {"ptext": ""})["ptext"]}'
                          : null,
                      icon: Icons.list_alt_rounded,
                      onTap: () async {
                        final ref = await showListaPicker(context);
                        if (ref != null)
                          setState(() => _pltypSelecionado = ref.pltyp);
                      },
                    ),

              // ── Seletor de grupo (condicional) ──
              if (_modo == SapModo.grupo) ...[
                const SizedBox(height: 16),
                _label('GRUPO DE CLIENTES (kdgrp)'),
                const SizedBox(height: 8),
                _carregando
                    ? const _LoadingField()
                    : _pickerButton(
                        hint: 'Selecione o grupo',
                        value: _kdgrpSelecionado != null
                            ? '$_kdgrpSelecionado  —  ${_grupos.firstWhere((g) => g["kdgrp"] == _kdgrpSelecionado, orElse: () => {"ktext": ""})["ktext"]}'
                            : null,
                        icon: Icons.account_tree_rounded,
                        onTap: () async {
                          final ref = await showGrupoPicker(context);
                          if (ref != null)
                            setState(() => _kdgrpSelecionado = ref.kdgrp);
                        },
                      ),
              ],

              const SizedBox(height: 24),

              // ── Range de datas ──
              _label('PERÍODO DE VIGÊNCIA'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _dataTile(
                      rotulo: 'Início',
                      valor: _formatarData(_datab),
                      icone: Icons.calendar_today_rounded,
                      onTap: () => _selecionarData(isInicio: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _dataTile(
                      rotulo: 'Fim',
                      valor: _formatarData(_datbi),
                      icone: Icons.event_rounded,
                      onTap: () => _selecionarData(isInicio: false),
                      opcional: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ── Botões ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: _corBorda),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        foregroundColor: _corSubtexto,
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _podeConfirmar
                          ? () => Navigator.of(context).pop(
                              _PrecoParams(
                                modo: _modo,
                                pltyp: _pltypSelecionado!,
                                kdgrp: _kdgrpSelecionado,
                                datab: _datab.date,
                                datbi: _datbi.date,
                                databOp: _datab.op.sapOp,
                                datbiOp: _datbi.op.sapOp,
                              ),
                            )
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: _corLaranja,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bolt_rounded, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Buscar do SAP',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modoCard({
    required SapModo modo,
    required String titulo,
    required String subtitulo,
    required IconData icon,
  }) {
    final ativo = _modo == modo;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _modo = modo;
          _kdgrpSelecionado = null; // limpa grupo ao trocar de modo
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ativo ? _corLaranja.withOpacity(0.06) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: ativo ? _corLaranja : _corBorda,
              width: ativo ? 1.8 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: ativo ? _corLaranja : _corSubtexto),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ativo ? _corLaranja : _corTexto,
                      ),
                    ),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: _corSubtexto,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String texto) => Text(
    texto,
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: _corSubtexto,
      letterSpacing: 0.9,
    ),
  );

  Widget _dropdown({
    required String hint,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) => DropdownButtonFormField<String>(
    value: value,
    hint: Text(hint, style: const TextStyle(fontSize: 13, color: _corSubtexto)),
    decoration: InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _corBorda),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _corBorda),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _corLaranja, width: 1.8),
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
    ),
    isExpanded: true,
    items: items,
    onChanged: onChanged,
    style: const TextStyle(
      fontSize: 13,
      color: _corTexto,
      fontWeight: FontWeight.w500,
    ),
  );

  Widget _dataTile({
    required String rotulo,
    required String valor,
    required IconData icone,
    required VoidCallback onTap,
    bool opcional = false,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _corBorda),
      ),
      child: Row(
        children: [
          Icon(icone, size: 16, color: _corLaranja),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rotulo + (opcional ? ' (opcional)' : ''),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: _corSubtexto,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _corTexto,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _pickerButton({
    required String hint,
    required String? value,
    required IconData icon,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value != null ? _corLaranja : _corBorda,
          width: value != null ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: value != null ? _corLaranja : _corSubtexto,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value ?? hint,
              style: TextStyle(
                fontSize: 13,
                fontWeight: value != null ? FontWeight.w600 : FontWeight.w400,
                color: value != null ? _corTexto : _corSubtexto,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.expand_more_rounded,
            size: 18,
            color: value != null ? _corLaranja : _corSubtexto,
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// DateOp — operador de comparação de data para o SAP
// ─────────────────────────────────────────────────────────────────────────────

enum DateOp { eq, gte, lte, neq }

extension DateOpExt on DateOp {
  String get label => switch (this) {
    DateOp.eq => '=',
    DateOp.gte => '>=',
    DateOp.lte => '<=',
    DateOp.neq => '<>',
  };
  String get sapOp => switch (this) {
    DateOp.eq => 'EQ',
    DateOp.gte => 'GE',
    DateOp.lte => 'LE',
    DateOp.neq => 'NE',
  };
  String get description => switch (this) {
    DateOp.eq => 'igual a',
    DateOp.gte => 'maior ou igual',
    DateOp.lte => 'menor ou igual',
    DateOp.neq => 'diferente de',
  };
}

class DateFilter {
  final DateOp op;
  final DateTime date;
  const DateFilter({required this.op, required this.date});
}

// Máscara DD/MM/AAAA sem dependência externa
class _DateMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue old,
    TextEditingValue next,
  ) {
    final digits = next.text.replaceAll(RegExp(r'\D'), '');
    final buf = StringBuffer();
    for (var i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// Dialog customizado: chips de operador + campo de texto com máscara
class DateFilterDialog extends StatefulWidget {
  final DateFilter? initial;
  final String label;

  const DateFilterDialog({
    super.key,
    required this.initial,
    required this.label,
  });

  @override
  State<DateFilterDialog> createState() => _DateFilterDialogState();
}

class _DateFilterDialogState extends State<DateFilterDialog> {
  static const _laranja = Color(0xFFFF6B00);

  late DateOp _op;
  late TextEditingController _ctrl;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _op = widget.initial?.op ?? DateOp.gte;
    final d = widget.initial?.date ?? DateTime.now();
    _ctrl = TextEditingController(
      text:
          '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.year}',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  DateTime? _parse() {
    final parts = _ctrl.text.split('/');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    if (y < 1900 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  void _confirmar() {
    final date = _parse();
    if (date == null) {
      setState(() => _erro = 'Data inválida. Use DD/MM/AAAA');
      return;
    }
    Navigator.of(context).pop(DateFilter(op: _op, date: date));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_month_outlined,
                  color: _laranja,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Text(
              'Operador',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: DateOp.values.map((op) {
                final sel = op == _op;
                return GestureDetector(
                  onTap: () => setState(() => _op = op),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? _laranja : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? _laranja : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          op.label,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: sel ? Colors.white : Colors.grey.shade800,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          op.description,
                          style: TextStyle(
                            fontSize: 11,
                            color: sel
                                ? Colors.white.withOpacity(0.85)
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            Text(
              'Data',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [_DateMaskFormatter()],
              style: const TextStyle(fontSize: 16, letterSpacing: 1),
              decoration: InputDecoration(
                hintText: 'DD/MM/AAAA',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: const Icon(
                  Icons.edit_calendar_outlined,
                  size: 18,
                  color: _laranja,
                ),
                errorText: _erro,
                errorStyle: const TextStyle(fontSize: 11),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _laranja, width: 1.8),
                ),
              ),
              onChanged: (_) {
                if (_erro != null) setState(() => _erro = null);
              },
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade600,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirmar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _laranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Confirmar',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingField extends StatelessWidget {
  const _LoadingField();
  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: const Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFFF6B00),
          ),
        ),
        SizedBox(width: 10),
        Text(
          'Carregando catálogo…',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      ],
    ),
  );
}
