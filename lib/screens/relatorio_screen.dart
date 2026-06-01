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
            ativo: _modo == SapModo.lista,
            onTap: () => setState(() {
              _modo = SapModo.lista;
              _grupoSelecionado = null;
            }),
          ),
          const SizedBox(width: 8),
          _modoChip(
            label: 'Lista + Grupo',
            icon: Icons.account_tree_rounded,
            ativo: _modo == SapModo.grupo,
            onTap: () => setState(() => _modo = SapModo.grupo),
          ),
          const SizedBox(width: 16),

          // Seletor de Lista — botão que abre o picker
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
            // Seletor de Grupo — botão que abre o picker
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
          FilledButton.icon(
            onPressed: _podeBuscar && !_loadingSap ? _consultarSap : null,
            icon: _loadingSap
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.bolt_rounded, size: 18),
            label: Text(_loadingSap ? 'Consultando…' : 'Consultar SAP'),
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
