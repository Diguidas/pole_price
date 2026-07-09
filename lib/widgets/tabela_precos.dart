import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/material_preco.dart';

const _laranja = Color(0xFFFF6B00);
const _azulInfo = Color(0xFF0EA5E9);

// ── Paleta das seções ────────────────────────────────────────────────────────
const _corAtualBg = Color(0xFFF0F6FF);
const _corAtualBorda = Color(0xFFBFD7FF);
const _corAtualLabel = Color(0xFF3B82F6);

const _corNovoBg = Color(0xFFFFF8F2);
const _corNovoBorda = Color(0xFFFFCCA0);
const _corNovoLabel = Color(0xFFFF6B00);

const _corOfertaBg = Color(0xFFF0FDF6);
const _corOfertaBorda = Color(0xFF86EFAC);
const _corOfertaLabel = Color(0xFF16A34A);

// Alturas e tamanhos base
const _labelFontSize = 10.0;
const _valorFontSize = 13.0;
const _inputFontSize = 13.0;
const _rowHPad = 16.0;

class TabelaPrecos extends StatefulWidget {
  final PrecoController controller;
  const TabelaPrecos({super.key, required this.controller});

  @override
  State<TabelaPrecos> createState() => _TabelaPrecosState();
}

class _TabelaPrecosState extends State<TabelaPrecos> {
  final ScrollController _scrollCtrl = ScrollController();
  String? _filtroAtivo;
  final Set<String> _selecionados = {};

  PrecoController get ctrl => widget.controller;

  List<MaterialPreco> get _listaExibida {
    final base = ctrl.filtrados;
    if (_filtroAtivo == null) return base;
    return base.where((m) {
      switch (_filtroAtivo) {
        case 'ok':
          return m.statusMargem == 'ok';
        case 'atencao':
          return m.statusMargem == 'atencao';
        case 'critico':
          return m.statusMargem == 'critico';
        case 'prejuizo':
          return m.statusMargem == 'prejuizo';
        case 'sem margem':
          return m.statusMargem == 'sem margem';
        case 'sem-cpv':
          return m.statusMargem == 'sem-cpv';
        case 'bloqueado':
          return m.bloqueado;
        case 'inativo':
          return m.inativo;
        default:
          return true;
      }
    }).toList();
  }

  void _alternarFiltro(String chave) =>
      setState(() => _filtroAtivo = _filtroAtivo == chave ? null : chave);

  void _alternarSelecao(String codigo, bool? valor) {
    setState(() {
      if (valor ?? false) {
        _selecionados.add(codigo);
      } else {
        _selecionados.remove(codigo);
      }
    });
  }

  void _alternarSelecionarTodas(List<MaterialPreco> lista) {
    setState(() {
      final todasSelecionadas =
          lista.isNotEmpty &&
          lista.every((m) => _selecionados.contains(m.codigo));
      if (todasSelecionadas) {
        for (final m in lista) {
          _selecionados.remove(m.codigo);
        }
      } else {
        for (final m in lista) {
          _selecionados.add(m.codigo);
        }
      }
    });
  }

  void _excluirSelecionados(List<MaterialPreco> lista) {
    final alvos = lista.where((m) => _selecionados.contains(m.codigo));
    ctrl.removerMateriais(alvos);
    setState(() => _selecionados.clear());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ctrl.pltyp == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.table_chart_outlined,
              size: 56,
              color: Colors.grey.shade200,
            ),
            const SizedBox(height: 14),
            Text(
              'Selecione uma tabela para ver os materiais',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final lista = _listaExibida;
    final todasSelecionadas =
        lista.isNotEmpty && lista.every((m) => _selecionados.contains(m.codigo));

    return Column(
      children: [
        RepaintBoundary(child: _legenda(ctrl.filtrados)),
        const SizedBox(height: 10),
        _cabecalho(),
        const SizedBox(height: 6),
        _barraSelecao(lista, todasSelecionadas),
        const SizedBox(height: 6),
        if (lista.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                _filtroAtivo != null
                    ? 'Nenhum material para este filtro'
                    : 'Nenhum material encontrado',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              itemCount: lista.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
              itemBuilder: (context, index) {
                final m = lista[index];
                return _ItemMaterial(
                  key: ValueKey(m.codigo),
                  material: m,
                  controller: ctrl,
                  isLast: index == lista.length - 1,
                  onChanged: () => setState(() {}),
                  onRemover: () => ctrl.removerMaterial(m),
                  selecionado: _selecionados.contains(m.codigo),
                  onSelecionarChanged: (v) => _alternarSelecao(m.codigo, v),
                );
              },
            ),
          ),
      ],
    );
  }

  // ── Barra de seleção múltipla ───────────────────────────────────────────────

  Widget _barraSelecao(List<MaterialPreco> lista, bool todasSelecionadas) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: todasSelecionadas,
              onChanged: lista.isEmpty
                  ? null
                  : (_) => _alternarSelecionarTodas(lista),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Selecionar todas',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (_selecionados.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              '${_selecionados.length} selecionado(s)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _laranja,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _confirmarExclusao(lista),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Excluir selecionados'),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmarExclusao(List<MaterialPreco> lista) async {
    final n = _selecionados.length;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir materiais'),
        content: Text(
          'Remover $n material${n == 1 ? '' : 'is'} selecionado${n == 1 ? '' : 's'} desta lista?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmou == true) _excluirSelecionados(lista);
  }

  // ── Cabeçalho ──────────────────────────────────────────────────────────────

  Widget _cabecalho() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ATUAL
          Expanded(
            flex: 6,
            child: _cabecalhoSecao(
              'ATUAL',
              _corAtualLabel,
              _corAtualBg,
              _corAtualBorda,
            ),
          ),
          const SizedBox(width: 10),

          // NOVO
          Expanded(
            flex: 7,
            child: _cabecalhoSecao(
              'NOVO',
              _corNovoLabel,
              _corNovoBg,
              _corNovoBorda,
            ),
          ),
          const SizedBox(width: 10),

          // OFERTA
          Expanded(
            flex: 3,
            child: _cabecalhoSecao(
              'OFERTA',
              _corOfertaLabel,
              _corOfertaBg,
              _corOfertaBorda,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cabecalhoSecao(
    String titulo,
    Color labelColor,
    Color bg,
    Color borda,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borda),
      ),
      child: Text(
        titulo,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: labelColor,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // ── Legenda / filtros ──────────────────────────────────────────────────────

  Widget _legenda(List<MaterialPreco> lista) {
    int ok = 0,
        atencao = 0,
        critico = 0,
        semMargem = 0,
        prejuizo = 0,
        semCpv = 0,
        bloqueados = 0,
        inativos = 0;

    for (final m in lista) {
      if (m.bloqueado) bloqueados++;
      if (m.inativo) inativos++;
      switch (m.statusMargem) {
        case 'ok':
          ok++;
          break;
        case 'atencao':
          atencao++;
          break;
        case 'critico':
          critico++;
          break;
        case 'prejuizo':
          prejuizo++;
          break;
        case 'sem margem':
          semMargem++;
          break;
        default:
          semCpv++;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _rowHPad, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${lista.length} materiais',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (ok > 0) _legendaBtn('ok', Colors.green, '$ok ok'),
                if (atencao > 0)
                  _legendaBtn('atencao', Colors.orange, '$atencao atenção'),
                if (critico > 0)
                  _legendaBtn('critico', Colors.deepOrange, '$critico crítico'),
                if (prejuizo > 0)
                  _legendaBtn(
                    'prejuizo',
                    Colors.red.shade900,
                    '$prejuizo prejuízo',
                  ),
                if (semMargem > 0)
                  _legendaBtn(
                    'sem margem',
                    Colors.red,
                    '$semMargem sem margem',
                  ),
                if (semCpv > 0)
                  _legendaBtn('sem-cpv', Colors.grey, '$semCpv sem CPV'),
                if (bloqueados > 0)
                  _legendaBtn(
                    'bloqueado',
                    Colors.red.shade400,
                    '$bloqueados bloqueado',
                    icon: Icons.lock_outline,
                  ),
                if (inativos > 0)
                  _legendaBtn(
                    'inativo',
                    Colors.orange.shade700,
                    '$inativos inativo',
                    icon: Icons.pause_circle_outline,
                  ),
              ],
            ),
          ),
          if (_filtroAtivo != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => setState(() => _filtroAtivo = null),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.filter_alt_off,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Limpar filtro',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendaBtn(String chave, Color cor, String label, {IconData? icon}) {
    final ativo = _filtroAtivo == chave;
    return GestureDetector(
      onTap: () => _alternarFiltro(chave),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: ativo ? cor.withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ativo ? cor : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon != null
                ? Icon(icon, size: 10, color: cor)
                : Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: cor,
                      shape: BoxShape.circle,
                    ),
                  ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: ativo ? cor : Colors.grey.shade600,
                fontWeight: ativo ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Item individual ──────────────────────────────────────────────────────────

class _ItemMaterial extends StatefulWidget {
  final MaterialPreco material;
  final PrecoController controller;
  final VoidCallback onChanged;
  final VoidCallback onRemover;
  final bool isLast;
  final bool selecionado;
  final ValueChanged<bool?> onSelecionarChanged;

  const _ItemMaterial({
    super.key,
    required this.material,
    required this.controller,
    required this.onChanged,
    required this.onRemover,
    required this.selecionado,
    required this.onSelecionarChanged,
    this.isLast = false,
  });

  @override
  State<_ItemMaterial> createState() => _ItemMaterialState();
}

class _ItemMaterialState extends State<_ItemMaterial> {
  late final TextEditingController _ppcNovoCtrl;
  late final TextEditingController _ppcOfertaCtrl;
  late final TextEditingController _ppvUnitNovoCtrl;
  late final TextEditingController _ppvCxNovoCtrl;
  late final TextEditingController _ppvUnitOfertaCtrl;
  late final TextEditingController _reajusteCtrl;
  late final TextEditingController _reajusteOfertaCtrl;

  MaterialPreco get m => widget.material;

  @override
  void initState() {
    super.initState();
    _ppcNovoCtrl = TextEditingController(
      text: m.ppcNovoOverride != null
          ? m.ppcNovoOverride!.toStringAsFixed(2)
          : '',
    );
    _ppcOfertaCtrl = TextEditingController(
      text: m.ppcOfertaOverride != null
          ? m.ppcOfertaOverride!.toStringAsFixed(2)
          : '',
    );
    _ppvUnitNovoCtrl = TextEditingController(
      text: m.ppvUnitNovoOverride != null
          ? m.ppvUnitNovoOverride!.toStringAsFixed(2)
          : '',
    );
    _ppvCxNovoCtrl = TextEditingController(
      text: m.ppvUnitNovoOverride != null && m.ppvCxNovo != null
          ? m.ppvCxNovo!.toStringAsFixed(2)
          : '',
    );
    _ppvUnitOfertaCtrl = TextEditingController(
      text: m.ppvUnitOfertaOverride != null
          ? m.ppvUnitOfertaOverride!.toStringAsFixed(2)
          : '',
    );
    _reajusteCtrl = TextEditingController(
      text: m.reajusteOverride != null
          ? (m.reajusteOverride! * 100).toStringAsFixed(2)
          : '',
    );
    _reajusteOfertaCtrl = TextEditingController();
    widget.controller.registerRefresh(m.codigo, _resincronizarControllers);
  }

  /// Resincroniza os campos de texto a partir do modelo — chamado quando o
  /// vínculo de preço do agrupamento recalcula este material a partir de
  /// outro (o TextEditingController não muda sozinho quando o override é
  /// setado de fora, já que o estado da linha sobrevive a rebuilds).
  void _resincronizarControllers() {
    setState(() {
      _ppcNovoCtrl.text = m.ppcNovoOverride != null
          ? m.ppcNovoOverride!.toStringAsFixed(2)
          : '';
      _ppvUnitNovoCtrl.text = m.ppvUnitNovoOverride != null
          ? m.ppvUnitNovoOverride!.toStringAsFixed(2)
          : '';
      final ppvCx = m.ppvCxNovo;
      _ppvCxNovoCtrl.text = ppvCx != null ? ppvCx.toStringAsFixed(2) : '';
      final reaj = m.reajustePct;
      _reajusteCtrl.text = reaj != null
          ? (reaj * 100).toStringAsFixed(2)
          : '';
    });
  }

  @override
  void dispose() {
    widget.controller.unregisterRefresh(m.codigo);
    _ppcNovoCtrl.dispose();
    _ppcOfertaCtrl.dispose();
    _ppvUnitNovoCtrl.dispose();
    _ppvCxNovoCtrl.dispose();
    _ppvUnitOfertaCtrl.dispose();
    _reajusteCtrl.dispose();
    _reajusteOfertaCtrl.dispose();
    super.dispose();
  }

  // ── Handlers bidirecionais (inalterados) ──────────────────────────────────

  void _sincronizarPpvCxNovoCtrl() {
    final ppvCx = m.ppvCxNovo;
    _ppvCxNovoCtrl.text = ppvCx != null ? ppvCx.toStringAsFixed(2) : '';
  }

  void _onPpcNovoChanged(String v) {
    final val = double.tryParse(v.replaceAll(',', '.'));
    m.ppcNovoOverride = val;
    m.ppvUnitNovoOverride = null;
    m.reajusteOverride = null;
    final ppvNovo = m.ppvUnitNovo;
    _ppvUnitNovoCtrl.text = ppvNovo != null ? ppvNovo.toStringAsFixed(2) : '';
    _sincronizarPpvCxNovoCtrl();
    final ppvCx = m.ppvCxNovo;
    if (ppvCx != null) m.novoPreco = ppvCx;
    widget.controller.aplicarVinculoAgrupamento(m);
    setState(() {});
    widget.onChanged();
  }

  void _onPpcNovoConfirmado(String v) {
    _onPpcNovoChanged(v);
    final ppvNovo = m.ppvUnitNovo;
    if (ppvNovo != null) _ppvUnitNovoCtrl.text = ppvNovo.toStringAsFixed(2);
    _sincronizarPpvCxNovoCtrl();
    final reaj = m.reajustePct;
    if (reaj != null) _reajusteCtrl.text = (reaj * 100).toStringAsFixed(2);
  }

  void _onPpvUnitNovoChanged(String v) {
    final val = double.tryParse(v.replaceAll(',', '.'));
    m.ppvUnitNovoOverride = val;
    if (val != null) {
      final ppcCalculado = m.ppcDePpvUnit(val);
      m.ppcNovoOverride = ppcCalculado;
      if (ppcCalculado != null)
        _ppcNovoCtrl.text = ppcCalculado.toStringAsFixed(2);
    }
    _sincronizarPpvCxNovoCtrl();
    final ppvCx = m.ppvCxNovo;
    if (ppvCx != null) m.novoPreco = ppvCx;
    setState(() {});
    widget.onChanged();
  }

  void _onPpvCxNovoChanged(String v) {
    final val = double.tryParse(v.replaceAll(',', '.'));
    final fator = m.fatorConversao;
    final ppvUnit = (val != null && fator != null && fator > 0)
        ? val / fator
        : null;
    m.ppvUnitNovoOverride = ppvUnit;
    _ppvUnitNovoCtrl.text = ppvUnit != null ? ppvUnit.toStringAsFixed(2) : '';
    if (ppvUnit != null) {
      final ppcCalculado = m.ppcDePpvUnit(ppvUnit);
      m.ppcNovoOverride = ppcCalculado;
      if (ppcCalculado != null) {
        _ppcNovoCtrl.text = ppcCalculado.toStringAsFixed(2);
      }
    }
    final ppvCx = m.ppvCxNovo;
    if (ppvCx != null) m.novoPreco = ppvCx;
    setState(() {});
    widget.onChanged();
  }

  void _onReajusteChanged(String v) {
    final val = double.tryParse(v.replaceAll(',', '.'));
    m.reajusteOverride = val != null ? val / 100 : null;
    if (val != null) {
      final ppvNovo = m.ppvUnitDeReajuste(val / 100);
      m.ppvUnitNovoOverride = ppvNovo;
      if (ppvNovo != null) {
        _ppvUnitNovoCtrl.text = ppvNovo.toStringAsFixed(2);
        final ppcCalc = m.ppcDePpvUnit(ppvNovo);
        m.ppcNovoOverride = ppcCalc;
        if (ppcCalc != null) _ppcNovoCtrl.text = ppcCalc.toStringAsFixed(2);
      }
    }
    _sincronizarPpvCxNovoCtrl();
    final ppvCx = m.ppvCxNovo;
    if (ppvCx != null) m.novoPreco = ppvCx;
    setState(() {});
    widget.onChanged();
  }

  void _onPpcOfertaChanged(String v) {
    final val = double.tryParse(v.replaceAll(',', '.'));
    m.ppcOfertaOverride = val;
    m.ppvUnitOfertaOverride = null;
    final ppvOferta = m.ppvUnitOferta;
    _ppvUnitOfertaCtrl.text = ppvOferta != null
        ? ppvOferta.toStringAsFixed(2)
        : '';
    _reajusteOfertaCtrl.clear();
    setState(() {});
    widget.onChanged();
  }

  void _onPpvUnitOfertaChanged(String v) {
    final val = double.tryParse(v.replaceAll(',', '.'));
    m.ppvUnitOfertaOverride = val;
    if (val != null) {
      final ppcCalculado = m.ppcOfertaDePpvUnit(val);
      m.ppcOfertaOverride = ppcCalculado;
      if (ppcCalculado != null) {
        _ppcOfertaCtrl.text = ppcCalculado.toStringAsFixed(2);
      }
    }
    _reajusteOfertaCtrl.clear();
    setState(() {});
    widget.onChanged();
  }

  void _onReajusteOfertaChanged(String v) {
    final val = double.tryParse(v.replaceAll(',', '.'));
    final ppvNovo = m.ppvUnitNovo;
    final ppvOferta = (val != null && ppvNovo != null)
        ? ppvNovo * (1 + val / 100)
        : null;
    m.ppvUnitOfertaOverride = ppvOferta;
    _ppvUnitOfertaCtrl.text = ppvOferta != null
        ? ppvOferta.toStringAsFixed(2)
        : '';
    if (ppvOferta != null) {
      final ppcCalculado = m.ppcOfertaDePpvUnit(ppvOferta);
      m.ppcOfertaOverride = ppcCalculado;
      if (ppcCalculado != null) {
        _ppcOfertaCtrl.text = ppcCalculado.toStringAsFixed(2);
      }
    }
    setState(() {});
    widget.onChanged();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final temRestricao = m.bloqueado || m.inativo;
    final statusNovo = m.statusMargem;
    final corLinha = _corStatus(statusNovo);

    // BoxDecoration não aceita borderRadius com bordas de cores diferentes
    // (a faixa de status à esquerda é colorida, o resto é cinza) — por isso
    // a faixa é um Container próprio dentro de um ClipRRect, e a borda
    // "uniforme" cinza fica num Container externo separado.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: corLinha),
              Expanded(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(14),
                  child: _corpoCard(temRestricao),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _corpoCard(bool temRestricao) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Topo: material + descrição ──────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 4, top: 2),
              child: SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: widget.selecionado,
                  onChanged: widget.onSelecionarChanged,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        m.codigo,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (temRestricao) ...[
                        const SizedBox(width: 6),
                        _chipRestricao(m),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    m.description.isNotEmpty ? m.description : m.codigo,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: m.description.isNotEmpty
                          ? Colors.black87
                          : Colors.grey.shade400,
                      fontStyle: m.description.isNotEmpty
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            if (m.cpv != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  'CPV R\$ ${m.cpv!.toStringAsFixed(2)}  ·  fator ${m.fatorConversao?.toStringAsFixed(1) ?? "—"}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 17,
                color: Colors.grey.shade300,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32),
              tooltip: 'Remover material',
              onPressed: widget.onRemover,
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Info: Atual / Novo / Oferta ──────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: _secaoAtual()),
            const SizedBox(width: 10),
            Expanded(flex: 7, child: _secaoNovo()),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: _secaoOferta()),
          ],
        ),
      ],
    );
  }

  // ── Seção ATUAL ───────────────────────────────────────────────────────────

  Widget _secaoAtual() {
    return _SecaoBox(
      bg: _corAtualBg,
      borda: _corAtualBorda,
      child: Row(
        children: [
          _Col(
            label: 'PPV CX',
            value: 'R\$ ${m.precoAtual.toStringAsFixed(2)}',
          ),
          _Col(
            label: 'PPV Unit',
            value: m.ppvUnitAtual != null
                ? 'R\$ ${m.ppvUnitAtual!.toStringAsFixed(2)}'
                : '—',
          ),
          _Col(
            label: 'PPC',
            value: m.ppcAtual != null
                ? 'R\$ ${m.ppcAtual!.toStringAsFixed(2)}'
                : '—',
            color: Colors.grey.shade400,
          ),
          _Col(
            label: 'MC% Cliente',
            value: m.margemClienteAtual != null
                ? '${(m.margemClienteAtual! * 100).toStringAsFixed(1)}%'
                : '—',
            color: Colors.grey.shade500,
          ),
          _Col(
            label: 'MC R\$',
            value: m.mcReaisAtual != null
                ? 'R\$ ${m.mcReaisAtual!.toStringAsFixed(2)}'
                : '—',
            color: Colors.grey.shade500,
          ),
          _Col(
            label: 'MC% Pole',
            value: m.mcPctAtual != null
                ? '${(m.mcPctAtual! * 100).toStringAsFixed(1)}%'
                : '—',
            color: m.mcPctAtual != null
                ? _corMargem(m.mcPctAtual!, m)
                : Colors.grey.shade400,
            bold: m.mcPctAtual != null,
          ),
        ],
      ),
    );
  }

  // ── Seção NOVO ────────────────────────────────────────────────────────────

  Widget _secaoNovo() {
    final ppvCxNovo = m.ppvCxNovo;
    final ppvUnitNovo = m.ppvUnitNovo;
    final mcCliente = m.margemClienteNovo;
    final mcReais = m.mcReaisNovo;
    final mcPct = m.mcPctNovo;
    final reaj = m.reajustePct;
    final statusNovo = m.statusMargem;

    return _SecaoBox(
      bg: _corNovoBg,
      borda: _corNovoBorda,
      child: Row(
        children: [
          // PPV CX (editável)
          _ColInput(
            label: 'PPV CX',
            controller: _ppvCxNovoCtrl,
            hint: ppvCxNovo != null ? ppvCxNovo.toStringAsFixed(2) : '0,00',
            onChanged: _onPpvCxNovoChanged,
            onSubmitted: _onPpvCxNovoChanged,
          ),
          // PPV Unit (editável)
          _ColInput(
            label: 'PPV Unit',
            controller: _ppvUnitNovoCtrl,
            hint: ppvUnitNovo != null ? ppvUnitNovo.toStringAsFixed(2) : '0,00',
            onChanged: _onPpvUnitNovoChanged,
            onSubmitted: _onPpvUnitNovoChanged,
          ),
          // PPC Novo (ponto de entrada, destaque)
          _ColInput(
            label: 'PPC Novo',
            controller: _ppcNovoCtrl,
            hint: '0,00',
            onChanged: _onPpcNovoChanged,
            onSubmitted: _onPpcNovoConfirmado,
            highlight: true,
            legenda: m.materialPaiCode != null && m.excecaoPrecoPct != null
                ? 'segue ${m.materialPaiCode} ${m.excecaoPrecoPct! >= 0 ? '+' : ''}${(m.excecaoPrecoPct! * 100).toStringAsFixed(0)}%'
                : null,
          ),
          // MC% Cliente
          _Col(
            label: 'MC% Cliente',
            value: mcCliente != null
                ? '${(mcCliente * 100).toStringAsFixed(1)}%'
                : '—',
            color: Colors.grey.shade500,
          ),
          // MC R$
          _Col(
            label: 'MC R\$',
            value: mcReais != null ? 'R\$ ${mcReais.toStringAsFixed(2)}' : '—',
            color: Colors.grey.shade500,
          ),
          // MC% Pole + semáforo
          mcPct != null
              ? _semaforoPct(mcPct, statusNovo)
              : _Col(
                  label: 'MC% Pole',
                  value: '—',
                  color: Colors.grey.shade400,
                ),
          // % Reajuste (editável)
          _ColInput(
            label: '% Reajuste',
            controller: _reajusteCtrl,
            hint: reaj != null ? '${(reaj * 100).toStringAsFixed(2)}' : '0,00',
            suffix: '%',
            onChanged: _onReajusteChanged,
            onSubmitted: _onReajusteChanged,
            color: reaj != null
                ? (reaj > 0
                      ? Colors.green.shade700
                      : reaj < 0
                      ? Colors.red
                      : Colors.grey.shade600)
                : null,
          ),
        ],
      ),
    );
  }

  // ── Seção OFERTA ──────────────────────────────────────────────────────────

  Widget _secaoOferta() {
    final ppvUnitOferta = m.ppvUnitOferta;
    final reajOferta =
        (ppvUnitOferta != null && m.ppvUnitNovo != null && m.ppvUnitNovo! > 0)
        ? (ppvUnitOferta / m.ppvUnitNovo!) - 1
        : null;

    return _SecaoBox(
      bg: _corOfertaBg,
      borda: _corOfertaBorda,
      child: Row(
        children: [
          _ColInput(
            label: '% Reajuste',
            controller: _reajusteOfertaCtrl,
            hint: reajOferta != null
                ? (reajOferta * 100).toStringAsFixed(2)
                : '0,00',
            suffix: '%',
            onChanged: _onReajusteOfertaChanged,
            onSubmitted: _onReajusteOfertaChanged,
            color: reajOferta != null
                ? (reajOferta < 0
                      ? Colors.green.shade700
                      : Colors.orange.shade700)
                : Colors.grey.shade400,
          ),
          _ColInput(
            label: 'PPV Unit',
            controller: _ppvUnitOfertaCtrl,
            hint: ppvUnitOferta != null ? ppvUnitOferta.toStringAsFixed(2) : '0,00',
            onChanged: _onPpvUnitOfertaChanged,
            onSubmitted: _onPpvUnitOfertaChanged,
            color: Colors.green.shade700,
          ),
          _ColInput(
            label: 'PPC Oferta',
            controller: _ppcOfertaCtrl,
            hint: '0,00',
            onChanged: _onPpcOfertaChanged,
            onSubmitted: _onPpcOfertaChanged,
          ),
        ],
      ),
    );
  }

  // ── Semáforo de margem ────────────────────────────────────────────────────

  // Auto-envolvido em Expanded+Padding, igual _Col/_ColInput, para poder
  // ser usado como filho direto de um Row de seção.
  Widget _semaforoPct(double mcPct, String status) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'MC% Pole',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: _labelFontSize,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconeStatus(status), size: 13, color: _corStatus(status)),
                const SizedBox(width: 3),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${(mcPct * 100).toStringAsFixed(1)}%',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: _corStatus(status),
                        fontWeight: FontWeight.bold,
                        fontSize: _valorFontSize,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Text(
              _labelStatus(status),
              style: TextStyle(
                fontSize: 10,
                color: _corStatus(status).withOpacity(0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipRestricao(MaterialPreco m) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (m.bloqueado) _chip('BLOQ', Colors.red.shade700, Colors.red.shade50),
        if (m.bloqueado && m.inativo) const SizedBox(width: 3),
        if (m.inativo)
          _chip('INAT', Colors.orange.shade800, Colors.orange.shade50),
      ],
    );
  }

  Widget _chip(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // margemFlat/margemOferta são Margem Cliente (usadas para calcular o
  // preço), não limiar de MC Pole — não fazem sentido como referência do
  // semáforo aqui. Sem uma margem mínima de MC Pole definida na política,
  // só distinguimos prejuízo de ok.
  Color _corMargem(double mc, MaterialPreco m) {
    if (mc < 0) return Colors.red.shade900;
    return Colors.green;
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'ok':
        return Colors.green;
      case 'atencao':
        return Colors.orange;
      case 'critico':
        return Colors.deepOrange;
      case 'sem margem':
        return Colors.red;
      case 'prejuizo':
        return Colors.red.shade900;
      default:
        return Colors.grey.shade300;
    }
  }

  IconData _iconeStatus(String status) {
    switch (status) {
      case 'ok':
        return Icons.check_circle_outline;
      case 'atencao':
        return Icons.warning_amber_outlined;
      case 'critico':
        return Icons.trending_down;
      case 'prejuizo':
        return Icons.money_off;
      case 'sem margem':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  String _labelStatus(String status) {
    switch (status) {
      case 'ok':
        return 'margem ok';
      case 'atencao':
        return 'atenção';
      case 'critico':
        return 'abaixo política';
      case 'prejuizo':
        return 'prejuízo';
      case 'sem margem':
        return 'sem margem';
      default:
        return 'sem CPV';
    }
  }
}

// ── Helpers de layout ─────────────────────────────────────────────────────────

/// Container padrão de seção (ATUAL / NOVO / OFERTA)
class _SecaoBox extends StatelessWidget {
  final Color bg;
  final Color borda;
  final Widget child;

  const _SecaoBox({required this.bg, required this.borda, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borda),
      ),
      child: child,
    );
  }
}

/// Coluna de valor somente leitura: label em cima, valor embaixo
class _Col extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool bold;

  const _Col({
    required this.label,
    required this.value,
    this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: _labelFontSize,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: _valorFontSize,
                  color: color ?? Colors.grey.shade700,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Coluna de input editável: label em cima, campo embaixo
class _ColInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final String? suffix;
  final bool highlight;
  final Color? color;
  final int flex;
  final String? legenda;

  const _ColInput({
    required this.label,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onSubmitted,
    this.suffix,
    this.highlight = false,
    this.color,
    this.flex = 1,
    this.legenda,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: _labelFontSize,
                color: highlight
                    ? _laranja.withOpacity(0.8)
                    : Colors.grey.shade400,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: _inputFontSize,
                color: color ?? (highlight ? _laranja : Colors.black87),
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                suffixText: suffix,
                suffixStyle: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 7,
                ),
                filled: true,
                fillColor: highlight
                    ? const Color(0xFFFFF3E8)
                    : Colors.white.withOpacity(0.9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: highlight
                        ? _laranja.withOpacity(0.4)
                        : Colors.grey.shade300,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: highlight ? _laranja : _azulInfo,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
            if (legenda != null) ...[
              const SizedBox(height: 2),
              Text(
                legenda!,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 9, color: Colors.teal.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
