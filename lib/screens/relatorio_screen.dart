// lib/screens/relatorio_screen.dart
//
// Dependências extraídas:
//   - lib/widgets/lista_picker.dart  → ListaRef, showListaPicker
//   - lib/widgets/grupo_picker.dart  → GrupoRef, showGrupoPicker
//   - lib/widgets/app_shell.dart     → DateFilterDialog, DateFilter, DateOp
//   - lib/widgets/grafico_vigencia.dart (painter inline abaixo)

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/service/sap_sync_service.dart';
import 'package:pole_price/models/material_preco.dart';
import 'package:pole_price/widgets/app_shell.dart';
import 'package:pole_price/widgets/lista_picker.dart';
import 'package:pole_price/widgets/grupo_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modelos internos
// ─────────────────────────────────────────────────────────────────────────────

class _PontoHistorico {
  final DateTime data;
  final double preco;
  final double? precoAnterior;
  final String draftId;
  const _PontoHistorico({
    required this.data,
    required this.preco,
    this.precoAnterior,
    required this.draftId,
  });
}

class _EntradaVigencia {
  final DateTime inicio;
  final DateTime? fim;
  final double preco;
  final String rawDatab;
  final String rawDatabi;

  const _EntradaVigencia({
    required this.inicio,
    this.fim,
    required this.preco,
    required this.rawDatab,
    required this.rawDatabi,
  });

  bool vigenteEm(DateTime dt) {
    final dInicio = DateTime(inicio.year, inicio.month, inicio.day);
    final dCheck = DateTime(dt.year, dt.month, dt.day);
    if (dCheck.isBefore(dInicio)) return false;
    if (fim == null) return true;
    final dFim = DateTime(fim!.year, fim!.month, fim!.day);
    return !dCheck.isAfter(dFim);
  }
}

class _MaterialAgrupado {
  final String codigo;
  final String? descricao;
  final List<MaterialPreco> entradas;

  const _MaterialAgrupado({
    required this.codigo,
    this.descricao,
    required this.entradas,
  });

  double get precoAtual {
    final hoje = DateTime.now();
    for (final e in entradas) {
      if (_estaVigenteHoje(e, hoje)) return e.precoAtual ?? 0.0;
    }
    final passados = entradas.where((e) {
      final datab = _parseSapDate(e.datab ?? '');
      return datab != null && !datab.isAfter(hoje);
    }).toList();
    if (passados.isNotEmpty) {
      passados.sort(
        (a, b) => (_parseSapDate(b.datab ?? '') ?? DateTime(0)).compareTo(
          _parseSapDate(a.datab ?? '') ?? DateTime(0),
        ),
      );
      return passados.first.precoAtual ?? 0.0;
    }
    return entradas.first.precoAtual ?? 0.0;
  }

  bool get temVigenciaHoje {
    final hoje = DateTime.now();
    return entradas.any((e) => _estaVigenteHoje(e, hoje));
  }

  static bool _estaVigenteHoje(MaterialPreco e, DateTime hoje) {
    final datab = _parseSapDate(e.datab ?? '');
    final datbi = _parseSapDate(e.datbi ?? '');
    if (datab == null) return false;
    final dInicio = DateTime(datab.year, datab.month, datab.day);
    final dHoje = DateTime(hoje.year, hoje.month, hoje.day);
    if (dHoje.isBefore(dInicio)) return false;
    if (datbi == null) return true;
    final dFim = DateTime(datbi.year, datbi.month, datbi.day);
    return !dHoje.isAfter(dFim);
  }

  static DateTime? _parseSapDate(String s) {
    if (s.length != 8) return null;
    try {
      return DateTime(
        int.parse(s.substring(0, 4)),
        int.parse(s.substring(4, 6)),
        int.parse(s.substring(6, 8)),
      );
    } catch (_) {
      return null;
    }
  }
}

enum _ModoRelatorio { lista, historico }
// ─────────────────────────────────────────────────────────────────────────────
// Tela Principal
// ─────────────────────────────────────────────────────────────────────────────

class RelatorioScreen extends StatefulWidget {
  const RelatorioScreen({super.key});

  @override
  State<RelatorioScreen> createState() => _RelatorioScreenState();
}

class _RelatorioScreenState extends State<RelatorioScreen> {
  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _slate100 = Color(0xFFF1F5F9);
  static const _bgSuave = Color(0xFFF8FAFC);
  static const _azul = Color(0xFF0EA5E9);
  static const _verde = Color(0xFF10B981);

  final _supabase = Supabase.instance.client;

  // ── Filtros ───────────────────────────────────────────────────────────────
  SapModo _modo = SapModo.lista;
  ListaRef? _listaSelecionada;
  GrupoRef? _grupoSelecionado;
  DateTime? _datab;
  DateTime? _datbi;
  String _databOp = 'GE';
  String _datbiOp = 'LE';

  // ── Resultado ─────────────────────────────────────────────────────────────
  bool _loadingSap = false;
  String? _erroSap;
  List<MaterialPreco> _materiais = [];
  List<_MaterialAgrupado> _materiaisAgrupados = [];
  String _busca = '';
  _MaterialAgrupado? _materialAtivo;

  // ── Histórico ─────────────────────────────────────────────────────────────
  // ── Modo da tela ──────────────────────────────────────────────────────────

  _ModoRelatorio _modoRelatorio = _ModoRelatorio.lista;

  // ── Estado do modo Histórico SAP ──────────────────────────────────────────
  final _codigosController = TextEditingController();
  List<String> get _codigosDigitados => _codigosController.text
      .split(RegExp(r'[,\n]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  bool _loadingHistoricoSap = false;
  List<_MaterialHistorico> _historicoMateriais = [];
  _MaterialHistorico? _materialHistoricoAtivo;
  _EntradaHistoricoSap? _entradaHistoricoAtiva;

  // ── Histórico (modo lista — inalterado) ───────────────────────────────────
  bool _loadingHistorico = false;

  List<_PontoHistorico> _historico = [];
  List<_EntradaVigencia> _vigencias = [];

  List<_MaterialAgrupado> get _materiaisFiltrados {
    if (_busca.trim().isEmpty) return _materiaisAgrupados;
    final b = _busca.toLowerCase();
    return _materiaisAgrupados
        .where(
          (m) =>
              m.codigo.toLowerCase().contains(b) ||
              (m.descricao ?? '').toLowerCase().contains(b),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    // Força rebuild ao digitar para habilitar o botão
    _codigosController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _codigosController.dispose();
    super.dispose();
  }

  bool get _podeBuscarAtual {
    if (_modoRelatorio == _ModoRelatorio.historico)
      return _codigosDigitados.isNotEmpty;
    return _podeBuscar;
  }

  bool get _isLoadingAtual => _modoRelatorio == _ModoRelatorio.historico
      ? _loadingHistoricoSap
      : _loadingSap;

  void _acaoBuscar() {
    if (_modoRelatorio == _ModoRelatorio.historico) {
      _buscarHistorico();
    } else {
      _consultarSap();
    }
  }

  bool get _podeBuscar =>
      _listaSelecionada != null &&
      (_modo == SapModo.lista || _grupoSelecionado != null);

  // ─────────────────────────────────────────────────────────────────────────
  // Ações
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _abrirListaPicker() async {
    final ref = await showListaPicker(context);
    if (ref == null) return;
    setState(() {
      _listaSelecionada = ref;
      _materiais = [];
      _materiaisAgrupados = [];
      _materialAtivo = null;
      _historico = [];
      _vigencias = [];
    });
  }

  Future<void> _abrirGrupoPicker() async {
    final ref = await showGrupoPicker(context);
    if (ref == null) return;
    setState(() => _grupoSelecionado = ref);
  }

  Future<void> _consultarSap() async {
    if (!_podeBuscar) return;

    setState(() {
      _loadingSap = true;
      _erroSap = null;
      _materiais = [];
      _materiaisAgrupados = [];
      _materialAtivo = null;
      _historico = [];
      _vigencias = [];
    });

    try {
      final sapSync = SapSyncService(_supabase);
      final databStr = _datab != null ? _formatSapDate(_datab!) : null;
      final datbiStr = _datbi != null ? _formatSapDate(_datbi!) : null;

      List<MaterialPreco> resultado;
      if (_modo == SapModo.lista) {
        resultado = await sapSync.fetchFromSapLista(
          pltyp: _listaSelecionada!.pltyp,
          datab: databStr,
          datbi: datbiStr,
          databOp: _datab != null ? _databOp : null,
          datbiOp: _datbi != null ? _datbiOp : null,
        );
      } else {
        resultado = await sapSync.fetchFromSapGrupo(
          pltyp: _listaSelecionada!.pltyp,
          kdgrp: _grupoSelecionado!.kdgrp,
          datab: databStr,
          datbi: datbiStr,
          databOp: _datab != null ? _databOp : null,
          datbiOp: _datbi != null ? _datbiOp : null,
        );
      }

      final Map<String, _MaterialAgrupado> mapa = {};
      for (final m in resultado) {
        final cod = m.codigo ?? '';
        if (!mapa.containsKey(cod)) {
          mapa[cod] = _MaterialAgrupado(
            codigo: cod,
            descricao: m.description,
            entradas: [m],
          );
        } else {
          mapa[cod]!.entradas.add(m);
        }
      }
      final agrupados = mapa.values.toList()
        ..sort((a, b) => a.codigo.compareTo(b.codigo));

      if (!mounted) return;
      setState(() {
        _materiais = resultado;
        _materiaisAgrupados = agrupados;
        _loadingSap = false;
      });
      if (agrupados.isNotEmpty) _selecionarMaterial(agrupados.first);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroSap = 'Erro ao consultar SAP: $e';
        _loadingSap = false;
      });
    }
  }

  Future<void> _buscarHistorico() async {
    final codigos = _codigosDigitados;
    if (codigos.isEmpty) return;

    setState(() {
      _loadingHistoricoSap = true;
      _historicoMateriais = [];
      _materialHistoricoAtivo = null;
      _entradaHistoricoAtiva = null;
      _erroSap = null;
    });

    try {
      final sapSync = SapSyncService(_supabase);
      final databStr = _datab != null ? _formatSapDate(_datab!) : null;
      final datbiStr = _datbi != null ? _formatSapDate(_datbi!) : null;

      final rawList = await sapSync.fetchHistoricoRaw(
        matnrs: codigos,
        datab: databStr,
        datbi: datbiStr,
        databOp: _datab != null ? _databOp : null,
        datbiOp: _datbi != null ? _datbiOp : null,
      );

      final matnrsLimpos = codigos
          .map((c) => c.trim().replaceAll(RegExp(r'^0+'), ''))
          .toList();
      final productsRes = await _supabase
          .from('products')
          .select('code, name')
          .inFilter('code', matnrsLimpos);
      final descMap = {
        for (final p in productsRes as List)
          p['code'].toString(): p['name'].toString(),
      };

      final materiais = rawList.map((json) {
        final mat = _MaterialHistorico.fromJson(json);
        if (descMap.containsKey(mat.matnr)) {
          return _MaterialHistorico(
            matnr: mat.matnr,
            descricao: descMap[mat.matnr],
            entradas: mat.entradas,
          );
        }
        return mat;
      }).toList();

      if (!mounted) return;
      setState(() {
        _historicoMateriais = materiais;
        _loadingHistoricoSap = false;
      });
      if (materiais.isNotEmpty) _selecionarMaterialHistorico(materiais.first);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroSap = 'Erro ao buscar histórico SAP: $e';
        _loadingHistoricoSap = false;
      });
    }
  }

  void _selecionarMaterialHistorico(_MaterialHistorico mat) {
    setState(() {
      _materialHistoricoAtivo = mat;
      _entradaHistoricoAtiva = mat.entradas.isNotEmpty
          ? mat.entradas.first
          : null;
    });
  }

  void _selecionarMaterial(_MaterialAgrupado material) {
    setState(() {
      _materialAtivo = material;
      _vigencias = _construirVigencias(material);
    });
    _carregarHistorico(material);
  }

  List<_EntradaVigencia> _construirVigencias(_MaterialAgrupado material) {
    final lista = <_EntradaVigencia>[];
    for (final e in material.entradas) {
      final datab = _parseSapDate(e.datab ?? '');
      if (datab == null) continue;
      lista.add(
        _EntradaVigencia(
          inicio: datab,
          fim: _parseSapDate(e.datbi ?? ''),
          preco: e.precoAtual ?? 0.0,
          rawDatab: e.datab ?? '',
          rawDatabi: e.datbi ?? '',
        ),
      );
    }
    lista.sort((a, b) => a.inicio.compareTo(b.inicio));
    return lista;
  }

  Future<void> _carregarHistorico(_MaterialAgrupado material) async {
    setState(() {
      _loadingHistorico = true;
      _historico = [];
    });
    try {
      final draftsRes = await _supabase
          .from('price_drafts')
          .select('id, reviewed_at')
          .eq('master_list_id', _listaSelecionada!.pltyp)
          .eq('status', 'approved')
          .order('reviewed_at');

      final drafts = (draftsRes as List).cast<Map<String, dynamic>>();
      final Map<String, DateTime> datasPorDraft = {};
      for (final d in drafts) {
        final rawDate = d['reviewed_at']?.toString();
        if (rawDate == null || rawDate == 'null') continue;
        datasPorDraft[d['id'].toString()] = DateTime.parse(rawDate).toLocal();
      }

      if (datasPorDraft.isEmpty) {
        if (mounted) setState(() => _loadingHistorico = false);
        return;
      }

      final itensRes = await _supabase
          .from('price_draft_items')
          .select('draft_id, old_price, new_price')
          .eq('product_id', material.codigo)
          .inFilter('draft_id', datasPorDraft.keys.toList());

      final pontos = <_PontoHistorico>[];
      for (final item in itensRes as List) {
        final draftId = item['draft_id']?.toString();
        if (draftId == null) continue;
        final data = datasPorDraft[draftId];
        if (data == null) continue;
        final preco = _toDouble(item['new_price']);
        if (preco == null) continue;
        pontos.add(
          _PontoHistorico(
            data: data,
            preco: preco,
            precoAnterior: _toDouble(item['old_price']),
            draftId: draftId,
          ),
        );
      }
      pontos.sort((a, b) => a.data.compareTo(b.data));

      if (mounted)
        setState(() {
          _historico = pontos;
          _loadingHistorico = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingHistorico = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _formatSapDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}'
      '${dt.month.toString().padLeft(2, '0')}'
      '${dt.day.toString().padLeft(2, '0')}';

  String _exibirData(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  String _opLabel(String sapOp) => switch (sapOp) {
    'GE' => '>=',
    'LE' => '<=',
    'EQ' => '=',
    'NE' => '<>',
    _ => '>=',
  };

  DateOp _toDateOp(String sapOp) => switch (sapOp) {
    'GE' => DateOp.gte,
    'LE' => DateOp.lte,
    'EQ' => DateOp.eq,
    'NE' => DateOp.neq,
    _ => DateOp.gte,
  };

  DateTime? _parseSapDate(String s) {
    if (s.length != 8) return null;
    try {
      return DateTime(
        int.parse(s.substring(0, 4)),
        int.parse(s.substring(4, 6)),
        int.parse(s.substring(6, 8)),
      );
    } catch (_) {
      return null;
    }
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Future<void> _pickDate({required bool isInicio}) async {
    final result = await showDialog<DateFilter>(
      context: context,
      builder: (_) => DateFilterDialog(
        initial: isInicio
            ? (_datab != null
                  ? DateFilter(op: _toDateOp(_databOp), date: _datab!)
                  : null)
            : (_datbi != null
                  ? DateFilter(op: _toDateOp(_datbiOp), date: _datbi!)
                  : null),
        label: isInicio ? 'Data início (datab)' : 'Data fim (datbi)',
      ),
    );
    if (result == null) return;
    setState(() {
      if (isInicio) {
        _datab = result.date;
        _databOp = result.op.sapOp;
        if (_datbi != null && _datbi!.isBefore(_datab!)) _datbi = null;
      } else {
        _datbi = result.date;
        _datbiOp = result.op.sapOp;
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgSuave,
      body: Column(
        children: [
          _TopBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _painelFiltros(),
                  const SizedBox(height: 20),
                  Expanded(child: _corpo()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Top Bar ──────────────────────────────────────────────────────────────

  Widget _TopBar() => Container(
    height: 72,
    padding: const EdgeInsets.symmetric(horizontal: 32),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: _slate100)),
      boxShadow: [BoxShadow(color: Color(0x06000000), blurRadius: 12)],
    ),
    child: const Row(
      children: [
        Icon(Icons.analytics_outlined, color: _laranja, size: 24),
        SizedBox(width: 14),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Relatório de Preços',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _slate900,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              'Consulta SAP ao vivo + histórico de alterações',
              style: TextStyle(
                fontSize: 12,
                color: _slate600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  // ── Painel de Filtros ────────────────────────────────────────────────────

  Widget _painelFiltros() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _slate200),
      ),
      child: Row(
        children: [
          // Modo
          _modoChip(
            label: 'Lista',
            icon: Icons.list_alt_rounded,
            ativo:
                _modoRelatorio == _ModoRelatorio.lista &&
                _modo == SapModo.lista,
            onTap: () => setState(() {
              _modoRelatorio = _ModoRelatorio.lista;
              _modo = SapModo.lista;
              _grupoSelecionado = null;
              _historicoMateriais = [];
              _materialHistoricoAtivo = null;
            }),
          ),
          const SizedBox(width: 8),
          _modoChip(
            label: 'Lista + Grupo',
            icon: Icons.account_tree_rounded,
            ativo:
                _modoRelatorio == _ModoRelatorio.lista &&
                _modo == SapModo.grupo,
            onTap: () => setState(() {
              _modoRelatorio = _ModoRelatorio.lista;
              _modo = SapModo.grupo;
              _historicoMateriais = [];
              _materialHistoricoAtivo = null;
            }),
          ),
          const SizedBox(width: 8),
          _modoChip(
            label: 'Histórico',
            icon: Icons.history_rounded,
            ativo: _modoRelatorio == _ModoRelatorio.historico,
            onTap: () => setState(() {
              _modoRelatorio = _ModoRelatorio.historico;
              _materiais = [];
              _materiaisAgrupados = [];
              _materialAtivo = null;
            }),
          ),
          const SizedBox(width: 16),

          if (_modoRelatorio == _ModoRelatorio.historico) ...[
            Flexible(
              flex: 4,
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _codigosController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Código(s) do material — separe por vírgula',
                    prefixIcon: const Icon(
                      Icons.qr_code_rounded,
                      size: 16,
                      color: _slate600,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: _bgSuave,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _slate200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _laranja),
                    ),
                  ),
                  onSubmitted: (_) => _buscarHistorico(),
                ),
              ),
            ),
          ] else ...[
            _seletorBtn(
              label: _listaSelecionada != null
                  ? '${_listaSelecionada!.pltyp} — ${_listaSelecionada!.ptext}'
                  : 'Selecionar lista…',
              icon: Icons.list_alt_rounded,
              preenchido: _listaSelecionada != null,
              cor: _laranja,
              onTap: _abrirListaPicker,
              onClear: _listaSelecionada != null
                  ? () => setState(() => _listaSelecionada = null)
                  : null,
            ),
            if (_modo == SapModo.grupo) ...[
              const SizedBox(width: 10),
              _seletorBtn(
                label: _grupoSelecionado != null
                    ? '${_grupoSelecionado!.kdgrp} — ${_grupoSelecionado!.ktext}'
                    : 'Selecionar grupo…',
                icon: Icons.account_tree_rounded,
                preenchido: _grupoSelecionado != null,
                cor: const Color(0xFF0EA5E9),
                onTap: _abrirGrupoPicker,
                onClear: _grupoSelecionado != null
                    ? () => setState(() => _grupoSelecionado = null)
                    : null,
              ),
            ],
          ],

          const SizedBox(width: 16),

          // Datas
          _dateTile(
            rotulo: 'Início (datab)',
            valor: _datab != null
                ? '${_opLabel(_databOp)} ${_exibirData(_datab!)}'
                : 'Qualquer',
            onTap: () => _pickDate(isInicio: true),
            onClear: _datab != null
                ? () => setState(() {
                    _datab = null;
                    _databOp = 'GE';
                  })
                : null,
          ),
          const SizedBox(width: 8),
          _dateTile(
            rotulo: 'Fim (datbi)',
            valor: _datbi != null
                ? '${_opLabel(_datbiOp)} ${_exibirData(_datbi!)}'
                : 'Qualquer',
            onTap: () => _pickDate(isInicio: false),
            onClear: _datbi != null
                ? () => setState(() {
                    _datbi = null;
                    _datbiOp = 'LE';
                  })
                : null,
          ),

          const SizedBox(width: 16),

          // Botão consultar
          // Botão consultar
          FilledButton.icon(
            onPressed: _podeBuscarAtual && !_isLoadingAtual
                ? _acaoBuscar
                : null,
            icon: _isLoadingAtual
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _modoRelatorio == _ModoRelatorio.historico
                        ? Icons.history_rounded
                        : Icons.bolt_rounded,
                    size: 18,
                  ),
            label: Text(
              _isLoadingAtual
                  ? 'Buscando…'
                  : (_modoRelatorio == _ModoRelatorio.historico
                        ? 'Buscar Histórico'
                        : 'Consultar SAP'),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _laranja,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Botão de seleção com badge preenchido quando selecionado
  Widget _seletorBtn({
    required String label,
    required IconData icon,
    required bool preenchido,
    required Color cor,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return Flexible(
      flex: 3,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: preenchido ? cor.withOpacity(0.06) : _bgSuave,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: preenchido ? cor : _slate200,
              width: preenchido ? 1.6 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: preenchido ? cor : _slate600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: preenchido ? FontWeight.w700 : FontWeight.w500,
                    color: preenchido ? cor : _slate600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: cor.withOpacity(0.6),
                    ),
                  ),
                )
              else
                Icon(Icons.expand_more_rounded, size: 16, color: _slate600),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modoChip({
    required String label,
    required IconData icon,
    required bool ativo,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ativo ? _laranja.withOpacity(0.07) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ativo ? _laranja : _slate200,
          width: ativo ? 1.8 : 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: ativo ? _laranja : _slate600),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ativo ? _laranja : _slate900,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _dateTile({
    required String rotulo,
    required String valor,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _bgSuave,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _slate200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_rounded, size: 13, color: _laranja),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rotulo,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: _slate600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _slate900,
                ),
              ),
            ],
          ),
          if (onClear != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onClear,
              child: const Icon(
                Icons.close_rounded,
                size: 13,
                color: _slate600,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  // ── Corpo ────────────────────────────────────────────────────────────────

  Widget _corpo() {
    // ── Modo Histórico SAP ────────────────────────────────────────────────────
    if (_modoRelatorio == _ModoRelatorio.historico) {
      if (_loadingHistoricoSap) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: _laranja),
              SizedBox(height: 16),
              Text(
                'Buscando histórico no SAP…',
                style: TextStyle(
                  fontSize: 14,
                  color: _slate600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }
      if (_erroSap != null) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFB91C1C),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _erroSap!,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      if (_historicoMateriais.isEmpty) {
        return const _EstadoVazio(
          icon: Icons.history_rounded,
          titulo: 'Nenhum histórico encontrado',
          subtitulo:
              'Digite o código de um material e clique em Buscar Histórico.',
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 340,
            child: _ColunaHistoricoSap(
              materiais: _historicoMateriais,
              materialAtivo: _materialHistoricoAtivo,
              entradaAtiva: _entradaHistoricoAtiva,
              onMaterialSelecionado: _selecionarMaterialHistorico,
              onEntradaSelecionada: (entrada) =>
                  setState(() => _entradaHistoricoAtiva = entrada),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _PainelDetalheHistorico(
              material: _materialHistoricoAtivo,
              entrada: _entradaHistoricoAtiva,
            ),
          ),
        ],
      );
    }

    // ── Modo Lista / Lista+Grupo (inalterado) ─────────────────────────────────
    if (!_loadingSap && _materiais.isEmpty && _erroSap == null) {
      return _EstadoVazio(
        icon: Icons.bolt_outlined,
        titulo: 'Nenhuma consulta realizada',
        subtitulo:
            'Selecione uma lista (e grupo, se necessário) e clique em Consultar SAP.',
      );
    }

    if (_loadingSap) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _laranja),
            SizedBox(height: 16),
            Text(
              'Consultando SAP…',
              style: TextStyle(
                fontSize: 14,
                color: _slate600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (_erroSap != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C)),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  _erroSap!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 340,
          child: _ColunaMateriais(
            materiaisAgrupados: _materiaisAgrupados,
            materiais: _materiais,
            materialAtivo: _materialAtivo,
            busca: _busca,
            onBuscaChanged: (v) => setState(() => _busca = v),
            onSelecionado: _selecionarMaterial,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _ColunaHistorico(
            materialAtivo: _materialAtivo,
            vigencias: _vigencias,
            historico: _historico,
            loadingHistorico: _loadingHistorico,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelos do modo Histórico SAP
// ─────────────────────────────────────────────────────────────────────────────

class _EntradaHistoricoSap {
  final String tipo;
  final String pltyp;
  final String kdgrp;
  final String datab;
  final String datbi;
  final double kbetr;
  final double? mxwrt;
  final double? kgSug;
  final double? kgMin;
  final String? perc;

  const _EntradaHistoricoSap({
    required this.tipo,
    required this.pltyp,
    required this.kdgrp,
    required this.datab,
    required this.datbi,
    required this.kbetr,
    this.mxwrt,
    this.kgSug,
    this.kgMin,
    this.perc,
  });

  factory _EntradaHistoricoSap.fromJson(Map<String, dynamic> json) {
    return _EntradaHistoricoSap(
      // Note que agora as chaves estão em MAIÚSCULAS para bater com o log do SAP
      tipo: (json['TIPO'] ?? '').toString().toUpperCase(),
      pltyp: (json['PLTYP'] ?? '').toString().trim(),
      kdgrp: (json['KDGRP'] ?? '').toString().trim(),
      datab: (json['DATAB'] ?? '').toString().trim(),
      datbi: (json['DATBI'] ?? '').toString().trim(),
      kbetr: double.tryParse(json['KBETR']?.toString() ?? '0') ?? 0,
      mxwrt: double.tryParse(json['MXWRT']?.toString() ?? ''),
      kgSug: double.tryParse(json['KG_SUG']?.toString() ?? ''),
      kgMin: double.tryParse(json['KG_MIN']?.toString() ?? ''),
      perc: json['PERC']?.toString(),
    );
  }

  bool get isGrupo => tipo == 'GRUPO';
  String get rotulo => isGrupo ? 'Lista $pltyp · Grupo $kdgrp' : 'Lista $pltyp';
  String get chaveAgrupamento =>
      isGrupo ? 'grupo:$pltyp:$kdgrp' : 'lista:$pltyp';
}

class _MaterialHistorico {
  final String matnr;
  final String? descricao;
  final List<_EntradaHistoricoSap> entradas;

  const _MaterialHistorico({
    required this.matnr,
    this.descricao,
    required this.entradas,
  });

  factory _MaterialHistorico.fromJson(Map<String, dynamic> json) {
    // SAP retorna chaves em MAIÚSCULAS
    final rawList = (json['HISTORICO'] ?? json['historico']) as List? ?? [];
    final matnr = (json['MATNR'] ?? json['matnr'] ?? '').toString().trim();
    return _MaterialHistorico(
      matnr: matnr.replaceAll(RegExp(r'^0+'), ''),
      descricao: json['descricao']?.toString(),
      entradas: rawList
          .whereType<Map<String, dynamic>>()
          .map(_EntradaHistoricoSap.fromJson)
          .toList(),
    );
  }

  Map<String, List<_EntradaHistoricoSap>> get porAgrupamento {
    final map = <String, List<_EntradaHistoricoSap>>{};
    for (final e in entradas) {
      map.putIfAbsent(e.chaveAgrupamento, () => []).add(e);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.datab.compareTo(b.datab));
    }
    return map;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: Coluna esquerda do modo Histórico SAP
// ─────────────────────────────────────────────────────────────────────────────

class _ColunaHistoricoSap extends StatefulWidget {
  final List<_MaterialHistorico> materiais;
  final _MaterialHistorico? materialAtivo;
  final _EntradaHistoricoSap? entradaAtiva;
  final ValueChanged<_MaterialHistorico> onMaterialSelecionado;
  final ValueChanged<_EntradaHistoricoSap> onEntradaSelecionada;

  const _ColunaHistoricoSap({
    required this.materiais,
    required this.materialAtivo,
    required this.entradaAtiva,
    required this.onMaterialSelecionado,
    required this.onEntradaSelecionada,
  });

  @override
  State<_ColunaHistoricoSap> createState() => _ColunaHistoricoSapState();
}

class _ColunaHistoricoSapState extends State<_ColunaHistoricoSap> {
  static const _laranja = Color(0xFFFF6B00);
  static const _azul = Color(0xFF0EA5E9);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _slate100 = Color(0xFFF1F5F9);
  static const _bgSuave = Color(0xFFF8FAFC);

  // Quais seções de categoria estão expandidas
  // chave = "matnr::listas" ou "matnr::grupos"
  final Set<String> _expandidos = {};

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, size: 16, color: _laranja),
                const SizedBox(width: 8),
                Text(
                  '${widget.materiais.length} material${widget.materiais.length == 1 ? '' : 'is'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _slate900,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _slate100),
          Expanded(
            child: ListView.builder(
              itemCount: widget.materiais.length,
              itemBuilder: (context, idx) {
                final mat = widget.materiais[idx];
                final materialAtivo = widget.materialAtivo?.matnr == mat.matnr;

                // Separa entradas em dois grupos: só-lista e lista+grupo
                final entradasLista = mat.entradas
                    .where((e) => !e.isGrupo)
                    .toList();
                final entradasGrupo = mat.entradas
                    .where((e) => e.isGrupo)
                    .toList();

                // Agrupa por chaveAgrupamento dentro de cada categoria
                Map<String, List<_EntradaHistoricoSap>> _agrupar(
                  List<_EntradaHistoricoSap> lista,
                ) {
                  final map = <String, List<_EntradaHistoricoSap>>{};
                  for (final e in lista) {
                    map.putIfAbsent(e.chaveAgrupamento, () => []).add(e);
                  }
                  return map;
                }

                final porLista = _agrupar(entradasLista);
                final porGrupo = _agrupar(entradasGrupo);

                final chaveListas = '${mat.matnr}::listas';
                final chaveGrupos = '${mat.matnr}::grupos';
                final listasExpandido = _expandidos.contains(chaveListas);
                final gruposExpandido = _expandidos.contains(chaveGrupos);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Nível 1: Material ──────────────────────────────────
                    InkWell(
                      onTap: () {
                        widget.onMaterialSelecionado(mat);
                        setState(() {
                          _expandidos.removeWhere(
                            (k) => k.startsWith('${mat.matnr}::'),
                          );
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 130),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        color: materialAtivo
                            ? _laranja.withOpacity(0.04)
                            : Colors.transparent,
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 130),
                              width: 3,
                              height: 40,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                color: materialAtivo
                                    ? _laranja
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mat.descricao ?? mat.matnr,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: materialAtivo
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: _slate900,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Text(
                                        mat.matnr,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontFamily: 'monospace',
                                          color: _slate600,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (porLista.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        _BadgeCategoria(
                                          label:
                                              '${porLista.length} lista${porLista.length == 1 ? '' : 's'}',
                                          cor: _laranja,
                                        ),
                                      ],
                                      if (porGrupo.isNotEmpty) ...[
                                        const SizedBox(width: 4),
                                        _BadgeCategoria(
                                          label:
                                              '${porGrupo.length} grupo${porGrupo.length == 1 ? '' : 's'}',
                                          cor: _azul,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              materialAtivo
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.keyboard_arrow_right_rounded,
                              size: 18,
                              color: materialAtivo ? _laranja : _slate600,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Nível 2 e 3 — só quando material ativo ────────────
                    if (materialAtivo) ...[
                      // ── Categoria: Listas ──────────────────────────────
                      if (porLista.isNotEmpty)
                        _SecaoCategoria(
                          titulo: 'Listas',
                          icone: Icons.list_alt_rounded,
                          cor: _laranja,
                          quantidade: porLista.length,
                          expandido: listasExpandido,
                          onToggle: () => setState(() {
                            listasExpandido
                                ? _expandidos.remove(chaveListas)
                                : _expandidos.add(chaveListas);
                          }),
                          // Nível 3: cada lista dentro da categoria
                          filhos: listasExpandido
                              ? porLista.entries.map((entry) {
                                  final primeira = entry.value.first;
                                  final selecionada =
                                      widget.entradaAtiva != null &&
                                      entry.value.contains(widget.entradaAtiva);
                                  return _ItemAgrupamento(
                                    rotulo: primeira.rotulo,
                                    qtdPeriodos: entry.value.length,
                                    cor: _laranja,
                                    selecionado: selecionada,
                                    onTap: () => widget.onEntradaSelecionada(
                                      entry.value.last,
                                    ),
                                  );
                                }).toList()
                              : [],
                        ),

                      // ── Categoria: Listas + Grupo ──────────────────────
                      if (porGrupo.isNotEmpty)
                        _SecaoCategoria(
                          titulo: 'Listas + Grupo',
                          icone: Icons.account_tree_rounded,
                          cor: _azul,
                          quantidade: porGrupo.length,
                          expandido: gruposExpandido,
                          onToggle: () => setState(() {
                            gruposExpandido
                                ? _expandidos.remove(chaveGrupos)
                                : _expandidos.add(chaveGrupos);
                          }),
                          filhos: gruposExpandido
                              ? porGrupo.entries.map((entry) {
                                  final primeira = entry.value.first;
                                  final selecionada =
                                      widget.entradaAtiva != null &&
                                      entry.value.contains(widget.entradaAtiva);
                                  return _ItemAgrupamento(
                                    rotulo: primeira.rotulo,
                                    qtdPeriodos: entry.value.length,
                                    cor: _azul,
                                    selecionado: selecionada,
                                    onTap: () => widget.onEntradaSelecionada(
                                      entry.value.last,
                                    ),
                                  );
                                }).toList()
                              : [],
                        ),
                    ],

                    if (idx < widget.materiais.length - 1)
                      const Divider(height: 1, color: _slate100),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nível 2 — Seção de categoria (Listas / Listas + Grupo)
// ─────────────────────────────────────────────────────────────────────────────

class _SecaoCategoria extends StatelessWidget {
  final String titulo;
  final IconData icone;
  final Color cor;
  final int quantidade;
  final bool expandido;
  final VoidCallback onToggle;
  final List<Widget> filhos;

  static const _slate100 = Color(0xFFF1F5F9);

  const _SecaoCategoria({
    required this.titulo,
    required this.icone,
    required this.cor,
    required this.quantidade,
    required this.expandido,
    required this.onToggle,
    required this.filhos,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 9, 16, 9),
            color: expandido ? cor.withOpacity(0.03) : Colors.transparent,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icone, size: 12, color: cor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$quantidade',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: cor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: expandido ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: cor.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          child: Column(children: filhos),
        ),
        const Divider(height: 1, color: _slate100),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nível 3 — Item de agrupamento (Lista X / Lista X · Grupo Y)
// ─────────────────────────────────────────────────────────────────────────────

class _ItemAgrupamento extends StatelessWidget {
  final String rotulo;
  final int qtdPeriodos;
  final Color cor;
  final bool selecionado;
  final VoidCallback onTap;

  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);

  const _ItemAgrupamento({
    required this.rotulo,
    required this.qtdPeriodos,
    required this.cor,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.fromLTRB(48, 10, 16, 10),
        color: selecionado ? cor.withOpacity(0.07) : Colors.transparent,
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selecionado ? cor : cor.withOpacity(0.3),
              ),
            ),
            Expanded(
              child: Text(
                rotulo,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selecionado ? FontWeight.w700 : FontWeight.w500,
                  color: selecionado ? cor : _slate900,
                ),
              ),
            ),
            Text(
              '$qtdPeriodos per.',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: selecionado ? cor.withOpacity(0.8) : _slate600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Badge pequeno para o cabeçalho do material
// ─────────────────────────────────────────────────────────────────────────────

class _BadgeCategoria extends StatelessWidget {
  final String label;
  final Color cor;

  const _BadgeCategoria({required this.label, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: cor.withOpacity(0.8),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: Painel direito do modo Histórico SAP
// ─────────────────────────────────────────────────────────────────────────────

class _PainelDetalheHistorico extends StatelessWidget {
  final _MaterialHistorico? material;
  final _EntradaHistoricoSap? entrada;

  static const _laranja = Color(0xFFFF6B00);
  static const _azul = Color(0xFF0EA5E9);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate200 = Color(0xFFE2E8F0);

  const _PainelDetalheHistorico({this.material, this.entrada});

  @override
  Widget build(BuildContext context) {
    if (material == null || entrada == null) {
      return const _EstadoVazio(
        icon: Icons.touch_app_outlined,
        titulo: 'Selecione um período',
        subtitulo:
            'Expanda um agrupamento e clique em um período para ver o gráfico.',
      );
    }

    // Monta vigências do mesmo agrupamento para o gráfico
    final vigencias =
        material!.entradas
            .where((e) => e.chaveAgrupamento == entrada!.chaveAgrupamento)
            .map((e) {
              final datab = _parseSapDate(e.datab);
              if (datab == null) return null;
              return _EntradaVigencia(
                inicio: datab,
                fim: _parseSapDate(e.datbi),
                preco: e.kbetr,
                rawDatab: e.datab,
                rawDatabi: e.datbi,
              );
            })
            .whereType<_EntradaVigencia>()
            .toList()
          ..sort((a, b) => a.inicio.compareTo(b.inicio));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card cabeçalho ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _slate200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        material!.descricao ?? material!.matnr,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: _slate900,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Código SAP: ${material!.matnr}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: _slate600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: (entrada!.isGrupo ? _azul : _laranja)
                            .withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            entrada!.isGrupo
                                ? Icons.account_tree_rounded
                                : Icons.list_alt_rounded,
                            size: 12,
                            color: entrada!.isGrupo ? _azul : _laranja,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            entrada!.rotulo,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: entrada!.isGrupo ? _azul : _laranja,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'PREÇO SELECIONADO',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: _slate600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'R\$ ${entrada!.kbetr.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: _laranja,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (entrada!.kgSug != null && entrada!.kgSug! > 0)
                      Text(
                        'Sugerido/kg: R\$ ${entrada!.kgSug!.toStringAsFixed(2).replaceAll('.', ',')}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _slate600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ── Card gráfico ──
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _slate200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.show_chart_rounded,
                      color: _laranja,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Evolução de Preço — Histórico SAP',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _slate900,
                      ),
                    ),
                    const Spacer(),
                    if (vigencias.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _laranja.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${vigencias.length} período${vigencias.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _laranja,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                vigencias.isEmpty
                    ? SizedBox(
                        height: 160,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bar_chart_rounded,
                                size: 40,
                                color: Colors.grey.shade200,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Sem períodos de vigência',
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _GraficoComScroll(vigencias: vigencias),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static DateTime? _parseSapDate(String s) {
    if (s.length != 8) return null;
    try {
      return DateTime(
        int.parse(s.substring(0, 4)),
        int.parse(s.substring(4, 6)),
        int.parse(s.substring(6, 8)),
      );
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widget: Coluna de Materiais
// ─────────────────────────────────────────────────────────────────────────────

class _ColunaMateriais extends StatelessWidget {
  final List<_MaterialAgrupado> materiaisAgrupados;
  final List<MaterialPreco> materiais;
  final _MaterialAgrupado? materialAtivo;
  final String busca;
  final ValueChanged<String> onBuscaChanged;
  final ValueChanged<_MaterialAgrupado> onSelecionado;

  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _slate100 = Color(0xFFF1F5F9);
  static const _bgSuave = Color(0xFFF8FAFC);

  const _ColunaMateriais({
    required this.materiaisAgrupados,
    required this.materiais,
    required this.materialAtivo,
    required this.busca,
    required this.onBuscaChanged,
    required this.onSelecionado,
  });

  List<_MaterialAgrupado> get _filtrados {
    if (busca.trim().isEmpty) return materiaisAgrupados;
    final b = busca.toLowerCase();
    return materiaisAgrupados
        .where(
          (m) =>
              m.codigo.toLowerCase().contains(b) ||
              (m.descricao ?? '').toLowerCase().contains(b),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 16,
                  color: _laranja,
                ),
                const SizedBox(width: 8),
                Text(
                  '${materiaisAgrupados.length} material${materiaisAgrupados.length == 1 ? '' : 'is'} (${materiais.length} registros SAP)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _slate900,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              onChanged: onBuscaChanged,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar código ou descrição…',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: _slate600,
                ),
                isDense: true,
                filled: true,
                fillColor: _bgSuave,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 9,
                  horizontal: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _slate200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _laranja),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: _slate100),
          Expanded(
            child: filtrados.isEmpty
                ? Center(
                    child: Text(
                      'Nenhum material encontrado',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtrados.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: _slate100),
                    itemBuilder: (context, i) {
                      final m = filtrados[i];
                      final ativo = materialAtivo?.codigo == m.codigo;
                      final vigente = m.temVigenciaHoje;

                      return InkWell(
                        onTap: () => onSelecionado(m),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 130),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          color: ativo
                              ? _laranja.withOpacity(0.04)
                              : Colors.transparent,
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 130),
                                width: 3,
                                height: 38,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  color: ativo ? _laranja : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m.descricao ?? m.codigo,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: ativo
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: _slate900,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Text(
                                          m.codigo,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            color: _slate600,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: vigente
                                                ? const Color(
                                                    0xFF10B981,
                                                  ).withOpacity(0.10)
                                                : Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            vigente
                                                ? 'Vigente'
                                                : 'Sem vigência',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: vigente
                                                  ? const Color(0xFF059669)
                                                  : Colors.grey.shade400,
                                            ),
                                          ),
                                        ),
                                        if (m.entradas.length > 1) ...[
                                          const SizedBox(width: 5),
                                          Text(
                                            '${m.entradas.length} períodos',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: _laranja.withOpacity(0.7),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'R\$ ${m.precoAtual.toStringAsFixed(2).replaceAll('.', ',')}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: ativo ? _laranja : _slate900,
                                ),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widget: Coluna de Histórico + Gráfico
// ─────────────────────────────────────────────────────────────────────────────

class _ColunaHistorico extends StatelessWidget {
  final _MaterialAgrupado? materialAtivo;
  final List<_EntradaVigencia> vigencias;
  final List<_PontoHistorico> historico;
  final bool loadingHistorico;

  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _slate100 = Color(0xFFF1F5F9);
  static const _bgSuave = Color(0xFFF8FAFC);

  const _ColunaHistorico({
    required this.materialAtivo,
    required this.vigencias,
    required this.historico,
    required this.loadingHistorico,
  });

  @override
  Widget build(BuildContext context) {
    if (materialAtivo == null) {
      return _EstadoVazio(
        icon: Icons.touch_app_outlined,
        titulo: 'Selecione um material',
        subtitulo: 'Clique em qualquer item da lista para ver o histórico.',
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardMaterial(),
          const SizedBox(height: 16),
          _cardGrafico(),
          const SizedBox(height: 16),
          if (!loadingHistorico && historico.isNotEmpty) _cardAuditoria(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _cardMaterial() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _slate200),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                materialAtivo!.descricao ?? materialAtivo!.codigo,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: _slate900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Código SAP: ${materialAtivo!.codigo}  •  ${materialAtivo!.entradas.length} período${materialAtivo!.entradas.length == 1 ? '' : 's'} no SAP',
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: _slate600,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: materialAtivo!.temVigenciaHoje
                    ? const Color(0xFF10B981).withOpacity(0.10)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    materialAtivo!.temVigenciaHoje
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 12,
                    color: materialAtivo!.temVigenciaHoje
                        ? const Color(0xFF059669)
                        : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    materialAtivo!.temVigenciaHoje
                        ? 'Preço vigente hoje'
                        : 'Sem preço vigente hoje',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: materialAtivo!.temVigenciaHoje
                          ? const Color(0xFF059669)
                          : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'PREÇO ATUAL',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: _slate600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'R\$ ${materialAtivo!.precoAtual.toStringAsFixed(2).replaceAll('.', ',')}',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: _laranja,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _cardGrafico() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _slate200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.show_chart_rounded, color: _laranja, size: 18),
            const SizedBox(width: 8),
            const Text(
              'Progressão de Preços (Períodos SAP)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _slate900,
              ),
            ),
            const Spacer(),
            if (vigencias.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _laranja.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${vigencias.length} período${vigencias.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _laranja,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        vigencias.isEmpty
            ? SizedBox(
                height: 160,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bar_chart_rounded,
                        size: 40,
                        color: Colors.grey.shade200,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sem períodos de vigência',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            // ── SCROLL HORIZONTAL quando muitos períodos ──────────────
            : _GraficoComScroll(vigencias: vigencias),
      ],
    ),
  );

  Widget _cardAuditoria() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _slate200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Text(
            'Trilha de Auditoria',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _slate900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: _bgSuave,
          child: const Row(
            children: [
              Expanded(flex: 3, child: _TabelaHeader('DATA DA MUDANÇA')),
              Expanded(flex: 3, child: _TabelaHeader('PREÇO ANTERIOR')),
              Expanded(flex: 3, child: _TabelaHeader('NOVO PREÇO')),
              Expanded(flex: 2, child: _TabelaHeader('VARIAÇÃO')),
              Expanded(
                flex: 4,
                child: _TabelaHeader('DRAFT ID', align: TextAlign.right),
              ),
            ],
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: historico.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: _slate100),
          itemBuilder: (context, idx) {
            final p = historico[idx];
            final anterior =
                p.precoAnterior ?? (idx > 0 ? historico[idx - 1].preco : null);
            double? diffPct;
            if (anterior != null && anterior > 0) {
              diffPct = ((p.preco - anterior) / anterior) * 100;
            }
            final corBadge = diffPct == null || diffPct == 0
                ? _slate600
                : (diffPct > 0
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444));
            final d = p.data;
            final dataStr =
                '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
                '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      dataStr,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _slate900,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      anterior != null
                          ? 'R\$ ${anterior.toStringAsFixed(2).replaceAll('.', ',')}'
                          : '—',
                      style: const TextStyle(color: _slate600),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'R\$ ${p.preco.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _slate900,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: diffPct == null
                        ? const Text('Base', style: TextStyle(color: _slate600))
                        : Text(
                            '${diffPct > 0 ? '+' : ''}${diffPct.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: corBadge,
                            ),
                          ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      p.draftId,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: _slate600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Gráfico com Scroll Horizontal
// Adapta a largura mínima por período para evitar sobreposição.
// ─────────────────────────────────────────────────────────────────────────────

class _GraficoComScroll extends StatefulWidget {
  final List<_EntradaVigencia> vigencias;
  static const double _minSlotWidth = 90.0;
  static const double _alturaGrafico = 300.0;

  const _GraficoComScroll({required this.vigencias});

  @override
  State<_GraficoComScroll> createState() => _GraficoComScrollState();
}

class _GraficoComScrollState extends State<_GraficoComScroll> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.vigencias.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraDisponivel = constraints.maxWidth;
        final larguraMinima = n * _GraficoComScroll._minSlotWidth;
        final larguraGrafico = larguraMinima > larguraDisponivel
            ? larguraMinima
            : larguraDisponivel;
        final precisaScroll = larguraMinima > larguraDisponivel;

        final grafico = SizedBox(
          height: _GraficoComScroll._alturaGrafico,
          width: larguraGrafico,
          child: CustomPaint(
            painter: _GraficoVigencia(vigencias: widget.vigencias),
          ),
        );

        if (!precisaScroll) return grafico;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.swipe_rounded,
                    size: 13,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Deslize para ver todos os ${n} períodos',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Scrollbar(
              controller: _scrollController, // 👈 controller explícito
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController, // 👈 mesmo controller
                scrollDirection: Axis.horizontal,
                child: grafico,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Estado vazio genérico
// ─────────────────────────────────────────────────────────────────────────────

class _EstadoVazio extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String subtitulo;

  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _bgSuave = Color(0xFFF8FAFC);

  const _EstadoVazio({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            color: _bgSuave,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 42, color: Colors.grey.shade300),
        ),
        const SizedBox(height: 16),
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _slate900,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 360,
          child: Text(
            subtitulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _slate600, height: 1.5),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Cabeçalho de tabela
// ─────────────────────────────────────────────────────────────────────────────

class _TabelaHeader extends StatelessWidget {
  final String label;
  final TextAlign align;
  const _TabelaHeader(this.label, {this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) => Text(
    label,
    textAlign: align,
    style: const TextStyle(
      fontSize: 10,
      letterSpacing: 0.7,
      fontWeight: FontWeight.w800,
      color: Color(0xFF475569),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Painter — Gráfico de Vigências SAP (inalterado)
// ─────────────────────────────────────────────────────────────────────────────

class _GraficoVigencia extends CustomPainter {
  final List<_EntradaVigencia> vigencias;
  const _GraficoVigencia({required this.vigencias});

  static const _laranja = Color(0xFFFF6B00);
  static const _verde = Color(0xFF10B981);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _slate400 = Color(0xFF94A3B8);

  @override
  void paint(Canvas canvas, Size size) {
    if (vigencias.isEmpty) return;

    final hoje = DateTime.now();
    final n = vigencias.length;

    const leftPad = 72.0;
    const rightPad = 20.0;
    const topPad = 16.0;
    const bottomPad = 52.0;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    final precos = vigencias.map((v) => v.preco).toList();
    double minP = precos.reduce((a, b) => a < b ? a : b);
    double maxP = precos.reduce((a, b) => a > b ? a : b);

    if (maxP == minP) {
      maxP += 10;
      minP = (minP - 10).clamp(0, double.infinity);
    } else {
      final pad = (maxP - minP) * 0.30;
      maxP += pad;
      minP = (minP - pad).clamp(0, double.infinity);
    }

    double precoToY(double p) {
      final pct = (p - minP) / (maxP - minP);
      return topPad + chartH * (1.0 - pct);
    }

    final slotW = chartW / n;
    double centerX(int i) => leftPad + slotW * i + slotW / 2;

    // Grid
    const gridLines = 4;
    final gridPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = 1.0;

    for (int g = 0; g <= gridLines; g++) {
      final y = topPad + chartH * (g / gridLines);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        gridPaint,
      );
      final val = maxP - ((maxP - minP) * (g / gridLines));
      _drawText(
        canvas,
        'R\$${val.toStringAsFixed(0)}',
        Offset(0, y - 7),
        const TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
        width: leftPad - 6,
        align: TextAlign.right,
      );
    }

    // Separadores verticais
    for (int i = 1; i < n; i++) {
      final x = leftPad + slotW * i;
      canvas.drawLine(
        Offset(x, topPad),
        Offset(x, topPad + chartH),
        Paint()
          ..color = _slate200.withOpacity(0.6)
          ..strokeWidth = 1.0,
      );
    }

    // Step-line
    if (n > 1) {
      final stepPath = Path();
      for (int i = 0; i < n; i++) {
        final cx = centerX(i);
        final cy = precoToY(vigencias[i].preco);
        if (i == 0) {
          stepPath.moveTo(cx, cy);
        } else {
          final prevCy = precoToY(vigencias[i - 1].preco);
          final midX = leftPad + slotW * i;
          stepPath.lineTo(midX, prevCy);
          stepPath.lineTo(midX, cy);
          stepPath.lineTo(cx, cy);
        }
      }
      canvas.drawPath(
        stepPath,
        Paint()
          ..color = _slate400.withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Pontos e labels
    for (int i = 0; i < n; i++) {
      final v = vigencias[i];
      final vigente = v.vigenteEm(hoje);
      final cor = vigente ? _verde : _laranja;
      final cx = centerX(i);
      final cy = precoToY(v.preco);

      canvas.drawRect(
        Rect.fromLTRB(
          leftPad + slotW * i + 2,
          topPad,
          leftPad + slotW * (i + 1) - 2,
          topPad + chartH,
        ),
        Paint()..color = cor.withOpacity(vigente ? 0.06 : 0.03),
      );

      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx, topPad + chartH),
        Paint()
          ..color = cor.withOpacity(0.15)
          ..strokeWidth = 2.0,
      );

      canvas.drawCircle(
        Offset(cx, cy),
        8.0,
        Paint()..color = cor.withOpacity(0.15),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        5.5,
        Paint()
          ..color = cor
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(cx, cy),
        2.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );

      final precoLabel =
          'R\$${v.preco.toStringAsFixed(2).replaceAll('.', ',')}';
      _drawText(
        canvas,
        precoLabel,
        Offset(cx - 36, cy - 22),
        TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w800),
        width: 72,
        align: TextAlign.center,
      );

      final label1 = 'Período ${i + 1}${vigente ? ' ✓' : ''}';
      _drawText(
        canvas,
        label1,
        Offset(cx - 40, topPad + chartH + 8),
        TextStyle(
          color: vigente ? _verde : _slate400,
          fontSize: 10,
          fontWeight: vigente ? FontWeight.w800 : FontWeight.w600,
        ),
        width: 80,
        align: TextAlign.center,
      );

      final d1 = v.inicio;
      final inicio =
          '${d1.day.toString().padLeft(2, '0')}/${d1.month.toString().padLeft(2, '0')}/${d1.year.toString().substring(2)}';
      final fim = v.fim != null
          ? '${v.fim!.day.toString().padLeft(2, '0')}/${v.fim!.month.toString().padLeft(2, '0')}/${v.fim!.year.toString().substring(2)}'
          : 'em aberto';
      _drawText(
        canvas,
        '$inicio→$fim',
        Offset(cx - 44, topPad + chartH + 22),
        TextStyle(
          color: _slate400.withOpacity(0.75),
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
        width: 88,
        align: TextAlign.center,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    double width = 80,
    TextAlign align = TextAlign.left,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: width);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _GraficoVigencia old) =>
      old.vigencias != vigencias;
}
