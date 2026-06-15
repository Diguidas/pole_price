import 'package:flutter/material.dart';
import 'package:pole_price/models/pricing_policy_model.dart';
import 'package:pole_price/service/pricing_policy_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PoliticasScreen extends StatefulWidget {
  const PoliticasScreen({super.key});

  @override
  State<PoliticasScreen> createState() => _PoliticasScreenState();
}

class _PoliticasScreenState extends State<PoliticasScreen> {
  static const _laranja      = Color(0xFFFF6B00);
  static const _slate900     = Color(0xFF0F172A);
  static const _slate600     = Color(0xFF475569);
  static const _slate100     = Color(0xFFF1F5F9);
  static const _bgSuave      = Color(0xFFF8FAFC);
  static const _verde        = Color(0xFF047857);
  static const _verdeLight   = Color(0xFFECFDF5);
  static const _roxo         = Color(0xFF7C3AED);
  static const _roxoLight    = Color(0xFFF5F3FF);
  static const _vermelho     = Color(0xFFEF4444);

  late final PricingPolicyService _service;

  bool _loading = true;
  List<PricingPolicy> _politicas = [];
  PricingPolicy? _selecionada;

  @override
  void initState() {
    super.initState();
    _service = PricingPolicyService(Supabase.instance.client);
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final lista = await _service.getPolicies();
      setState(() {
        _politicas = lista;
        if (_selecionada != null) {
          _selecionada = lista.where((p) => p.id == _selecionada!.id).firstOrNull;
        }
        _loading = false;
      });
    } catch (e) {
      _snack('Erro ao carregar políticas: $e', erro: true);
      setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          erro ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
          color: Colors.white, size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14))),
      ]),
      backgroundColor: erro ? _vermelho : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── FORMULÁRIO DE POLÍTICA ────────────────────────────────────────────────

  Future<void> _abrirFormulario({PricingPolicy? politica}) async {
    final isEdicao = politica != null;
    final nomeCtrl = TextEditingController(text: isEdicao ? politica.name : '');
    final flatCtrl = TextEditingController(
      text: politica?.margemFlat != null ? (politica!.margemFlat! * 100).toStringAsFixed(0) : '',
    );
    final ofertaCtrl = TextEditingController(
      text: politica?.margemOferta != null ? (politica!.margemOferta! * 100).toStringAsFixed(0) : '',
    );
    final descCtrl = TextEditingController(text: politica?.descricao ?? '');

    final salvo = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'FormularioPolitica',
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, animation, _, __) {
        final scale = Tween<double>(begin: 0.92, end: 1.0)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeInOutBack));
        return Opacity(
          opacity: animation.value,
          child: Transform.scale(
            scale: scale.value,
            child: AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              titlePadding: EdgeInsets.zero,
              contentPadding: const EdgeInsets.fromLTRB(32, 24, 32, 12),
              actionsPadding: const EdgeInsets.fromLTRB(32, 12, 32, 28),
              title: Container(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _slate100))),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _laranja.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome_motion_rounded, color: _laranja, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    isEdicao ? 'Editar Política' : 'Nova Política de Margem',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _slate900, letterSpacing: -0.5),
                  ),
                ]),
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _campoPremium(controller: nomeCtrl, label: 'Nome da Política', hint: 'Ex: Varejo Sul', icon: Icons.label_important_outline_rounded, textoSimples: true),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(child: _campoPremium(controller: flatCtrl, label: 'Margem Flat', hint: '30', icon: Icons.trending_up_rounded, suffixText: '%')),
                      const SizedBox(width: 16),
                      Expanded(child: _campoPremium(controller: ofertaCtrl, label: 'Margem Oferta', hint: '25', icon: Icons.local_offer_outlined, suffixText: '%')),
                    ]),
                    const SizedBox(height: 18),
                    _campoPremium(controller: descCtrl, label: 'Observações', hint: 'Informe o objetivo...', icon: Icons.description_outlined, textoSimples: true, maxLines: 2),
                  ]),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(foregroundColor: _slate600, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _laranja, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(isEdicao ? 'Salvar Alterações' : 'Criar Política', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (salvo != true) return;
    final nome = nomeCtrl.text.trim();
    if (nome.isEmpty) { _snack('O nome é obrigatório.', erro: true); return; }

    try {
      if (isEdicao) {
        await _service.updatePolicy(id: politica.id, name: nome, margemFlat: _parsePercent(flatCtrl.text), margemOferta: _parsePercent(ofertaCtrl.text), descricao: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim());
        _snack('Política atualizada!');
      } else {
        await _service.createPolicy(id: 'POL-${DateTime.now().millisecondsSinceEpoch}', name: nome, margemFlat: _parsePercent(flatCtrl.text), margemOferta: _parsePercent(ofertaCtrl.text), descricao: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim());
        _snack('Política criada!');
      }
      _carregar();
    } catch (e) {
      _snack('Erro: $e', erro: true);
    }
  }

  // ── CONFIRMAR EXCLUSÃO ────────────────────────────────────────────────────

  Future<void> _confirmarExclusao(PricingPolicy p) async {
    final confirmado = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ConfirmarExclusao',
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, animation, _, __) => FadeTransition(
        opacity: animation,
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: _vermelho, size: 24),
            SizedBox(width: 12),
            Text('Excluir Política', style: TextStyle(fontWeight: FontWeight.w800, color: _slate900)),
          ]),
          content: RichText(text: TextSpan(
            style: const TextStyle(fontSize: 14, color: _slate600, height: 1.5),
            children: [
              const TextSpan(text: 'A política '),
              TextSpan(text: p.name, style: const TextStyle(fontWeight: FontWeight.w800, color: _slate900)),
              const TextSpan(text: ' será removida e todas as listas vinculadas serão desvinculadas.'),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: _slate600, fontWeight: FontWeight.w600))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _vermelho, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (confirmado != true) return;
    try {
      await _service.deletePolicy(p.id);
      setState(() { if (_selecionada?.id == p.id) _selecionada = null; });
      _snack('Política removida.', erro: true);
      _carregar();
    } catch (e) {
      _snack('Erro ao excluir: $e', erro: true);
    }
  }

  // ── MODAL: VINCULAR LISTA ─────────────────────────────────────────────────

  Future<void> _abrirVincularLista(PricingPolicy politica) async {
    List<AllPriceList> todasListas = [];
    bool carregando = true;
    final listasSelecionadas = <String>{};

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          if (carregando) {
            _service.getAllPriceLists().then((listas) {
              setLocal(() { todasListas = listas; carregando = false; });
            });
          }

          final jaVinculadas = politica.listas.map((l) => l.id).toSet();

          return Dialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: SizedBox(
              width: 560,
              height: 580,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 28, 24, 16),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _laranja.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.link_rounded, color: _laranja, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Vincular Tabelas de Preço', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _slate900)),
                      Text('Política: ${politica.name}', style: const TextStyle(fontSize: 12, color: _laranja, fontWeight: FontWeight.w600)),
                    ])),
                    IconButton(icon: const Icon(Icons.close_rounded, color: _slate600), onPressed: () => Navigator.pop(ctx)),
                  ]),
                ),
                const Divider(height: 1, color: _slate100),

                // Lista
                Expanded(
                  child: carregando
                      ? const Center(child: CircularProgressIndicator(color: _laranja))
                      : todasListas.isEmpty
                          ? Center(child: Text('Nenhuma lista disponível', style: TextStyle(color: Colors.grey.shade400)))
                          : ListView.builder(
                              itemCount: todasListas.length,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              itemBuilder: (_, i) {
                                final l = todasListas[i];
                                final jaNestaPolitica = jaVinculadas.contains(l.id);
                                // Lista já em OUTRA política — bloqueada
                                final emOutra = l.vinculada && l.policyId != politica.id;
                                final selecionada = listasSelecionadas.contains(l.id);
                                final bloqueada = emOutra; // não pode vincular a duas

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: bloqueada
                                        ? const Color(0xFFFEF2F2)
                                        : jaNestaPolitica
                                            ? _verdeLight
                                            : selecionada
                                                ? _laranja.withOpacity(0.04)
                                                : Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: bloqueada
                                          ? _vermelho.withOpacity(0.2)
                                          : jaNestaPolitica
                                              ? const Color(0xFFDCFCE7)
                                              : selecionada
                                                  ? _laranja.withOpacity(0.3)
                                                  : _slate100,
                                    ),
                                  ),
                                  child: CheckboxListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    dense: true,
                                    value: jaNestaPolitica || selecionada,
                                    // Bloqueada se já está em outra política ou já está nesta
                                    onChanged: (bloqueada || jaNestaPolitica)
                                        ? null
                                        : (v) => setLocal(() => v == true
                                            ? listasSelecionadas.add(l.id)
                                            : listasSelecionadas.remove(l.id)),
                                    activeColor: _laranja,
                                    checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    title: Text(l.description,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: bloqueada ? _vermelho.withOpacity(0.7) : _slate900,
                                        )),
                                    subtitle: Text('ID: ${l.id}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontFamily: 'monospace')),
                                    secondary: bloqueada
                                        ? _pill('Outra política', const Color(0xFFFEE2E2), _vermelho)
                                        : jaNestaPolitica
                                            ? _pill('Vinculada ✓', _verdeLight, _verde)
                                            : _pill('Disponível', _slate100, _slate600),
                                  ),
                                );
                              },
                            ),
                ),

                // Footer
                const Divider(height: 1, color: _slate100),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
                  child: Row(children: [
                    Text('${listasSelecionadas.length} selecionada(s)',
                        style: const TextStyle(fontSize: 13, color: _slate600, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: _slate600))),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _laranja, elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: listasSelecionadas.isEmpty ? null : () async {
                        Navigator.pop(ctx);
                        int vinculadas = 0;
                        for (final id in listasSelecionadas) {
                          try {
                            await _service.vincularLista(listaId: id, policyId: politica.id);
                            vinculadas++;
                          } catch (e) {
                            _snack('Falha ao vincular $id: $e', erro: true);
                          }
                        }
                        if (vinculadas > 0) {
                          _snack('$vinculadas lista(s) vinculada(s) com sucesso!');
                          _carregar();
                        }
                      },
                      child: const Text('Confirmar Vínculo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── MODAL: EXCEÇÃO DE MARGEM ──────────────────────────────────────────────

  Future<void> _abrirExcecao(PolicyPriceList lista, PricingPolicy politica) async {
    final flatCtrl = TextEditingController(
      text: lista.excecaoFlatPct != null ? (lista.excecaoFlatPct! * 100).toStringAsFixed(1) : '',
    );
    final ofertaCtrl = TextEditingController(
      text: lista.excecaoOfertaPct != null ? (lista.excecaoOfertaPct! * 100).toStringAsFixed(1) : '',
    );

    // Margem efetiva = política + exceção
    double? flatEfetivo() {
      final base = politica.margemFlat ?? 0;
      final delta = _parsePercent(flatCtrl.text) ?? 0;
      return base + delta;
    }
    double? ofertaEfetivo() {
      final base = politica.margemOferta ?? 0;
      final delta = _parsePercent(ofertaCtrl.text) ?? 0;
      return base + delta;
    }

    final salvo = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(28, 24, 20, 20),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _slate100))),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: _roxoLight, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.tune_rounded, color: _roxo, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Exceção de Margem', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _slate900)),
                    Text(lista.description, style: const TextStyle(fontSize: 12, color: _slate600), overflow: TextOverflow.ellipsis),
                  ])),
                  IconButton(icon: const Icon(Icons.close_rounded, color: _slate600), onPressed: () => Navigator.pop(ctx, false)),
                ]),
              ),

              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Explicação
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: _roxoLight, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded, color: _roxo, size: 16),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        'O delta é somado à margem da política. Use valores negativos para reduzir.\nEx: política 30% + delta +4% = margem efetiva 34%',
                        style: const TextStyle(fontSize: 12, color: _roxo, height: 1.4),
                      )),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // Campos de delta
                  Row(children: [
                    Expanded(child: _campoPremium(
                      controller: flatCtrl,
                      label: 'Delta Flat',
                      hint: '+4 ou -2',
                      icon: Icons.trending_up_rounded,
                      suffixText: '%',
                      onChanged: (_) => setLocal(() {}),
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: _campoPremium(
                      controller: ofertaCtrl,
                      label: 'Delta Oferta',
                      hint: '+4 ou -2',
                      icon: Icons.local_offer_outlined,
                      suffixText: '%',
                      onChanged: (_) => setLocal(() {}),
                    )),
                  ]),
                  const SizedBox(height: 20),

                  // Preview efetivo
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _verdeLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _verde.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle_outline_rounded, color: _verde, size: 16),
                      const SizedBox(width: 10),
                      Expanded(child: RichText(text: TextSpan(
                        style: const TextStyle(fontSize: 13, color: _verde),
                        children: [
                          const TextSpan(text: 'Margem efetiva desta lista: '),
                          TextSpan(
                            text: 'Flat ${_fmtPct(flatEfetivo())}  ·  Oferta ${_fmtPct(ofertaEfetivo())}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ))),
                    ]),
                  ),

                  // Aviso espelho se tiver filhas
                  if (lista.temEspelhos) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _laranja.withOpacity(0.2)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.copy_all_rounded, color: _laranja, size: 16),
                        const SizedBox(width: 10),
                        Expanded(child: Text(
                          '${lista.mirrorFilhas.length} lista(s) espelho serão atualizadas automaticamente.',
                          style: const TextStyle(fontSize: 12, color: _laranja),
                        )),
                      ]),
                    ),
                  ],
                ]),
              ),

              // Actions
              Container(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                child: Row(children: [
                  // Remover exceção
                  if (lista.temExcecao)
                    TextButton.icon(
                      icon: const Icon(Icons.remove_circle_outline, size: 16, color: _vermelho),
                      label: const Text('Remover exceção', style: TextStyle(color: _vermelho, fontSize: 13)),
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(foregroundColor: _vermelho),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar', style: TextStyle(color: _slate600)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _roxo, elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Salvar Exceção', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );

    if (salvo != true) return;
    try {
      await _service.salvarExcecao(
        listaId: lista.id,
        excecaoFlatPct: _parsePercent(flatCtrl.text),
        excecaoOfertaPct: _parsePercent(ofertaCtrl.text),
      );
      _snack('Exceção salva${lista.temEspelhos ? " e propagada para ${lista.mirrorFilhas.length} espelho(s)" : ""}!');
      _carregar();
    } catch (e) {
      _snack('Erro ao salvar exceção: $e', erro: true);
    }
  }

  // ── MODAL: DEFINIR ESPELHO ────────────────────────────────────────────────

  Future<void> _abrirDefinirEspelho(PolicyPriceList listaMae, PricingPolicy politica) async {
    List<AllPriceList> todasListas = [];
    bool carregando = true;
    String? filhaSelecionada;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          if (carregando) {
            _service.getAllPriceLists().then((listas) {
              setLocal(() {
                // Exclui: a própria lista mãe, listas já espelho desta mãe, listas em outra política
                todasListas = listas.where((l) =>
                  l.id != listaMae.id &&
                  !listaMae.mirrorFilhas.contains(l.id) &&
                  (l.policyId == null || l.policyId == politica.id)
                ).toList();
                carregando = false;
              });
            });
          }

          return Dialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: SizedBox(
              width: 520,
              height: 520,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(28, 24, 20, 20),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _slate100))),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _laranja.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.copy_all_rounded, color: _laranja, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Adicionar Espelho', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _slate900)),
                      Text('Mãe: ${listaMae.description}', style: const TextStyle(fontSize: 12, color: _laranja, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    ])),
                    IconButton(icon: const Icon(Icons.close_rounded, color: _slate600), onPressed: () => Navigator.pop(ctx)),
                  ]),
                ),

                // Info
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: _laranja.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded, color: _laranja, size: 16),
                      const SizedBox(width: 10),
                      const Expanded(child: Text(
                        'A lista espelho herda a exceção de margem da lista mãe e acompanha automaticamente qualquer alteração futura.',
                        style: TextStyle(fontSize: 12, color: _laranja, height: 1.4),
                      )),
                    ]),
                  ),
                ),

                // Lista de disponíveis
                Expanded(
                  child: carregando
                      ? const Center(child: CircularProgressIndicator(color: _laranja))
                      : todasListas.isEmpty
                          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.folder_off_outlined, size: 36, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text('Nenhuma lista disponível para espelho', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                            ]))
                          : ListView.builder(
                              padding: const EdgeInsets.all(20),
                              itemCount: todasListas.length,
                              itemBuilder: (_, i) {
                                final l = todasListas[i];
                                final sel = filhaSelecionada == l.id;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: sel ? _laranja.withOpacity(0.05) : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: sel ? _laranja.withOpacity(0.4) : _slate100),
                                  ),
                                  child: RadioListTile<String>(
                                    value: l.id,
                                    groupValue: filhaSelecionada,
                                    onChanged: (v) => setLocal(() => filhaSelecionada = v),
                                    activeColor: _laranja,
                                    title: Text(l.description, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _slate900)),
                                    subtitle: Text('ID: ${l.id}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: _slate600)),
                                    secondary: l.vinculada
                                        ? _pill('Mesma política', _verdeLight, _verde)
                                        : _pill('Será vinculada', _slate100, _slate600),
                                  ),
                                );
                              },
                            ),
                ),

                // Footer
                const Divider(height: 1, color: _slate100),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
                  child: Row(children: [
                    const Spacer(),
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: _slate600))),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _laranja, elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: filhaSelecionada == null ? null : () async {
                        Navigator.pop(ctx);
                        try {
                          await _service.definirEspelho(
                            listaMaeId: listaMae.id,
                            listaFilhaId: filhaSelecionada!,
                            policyId: politica.id,
                          );
                          _snack('Espelho definido! A lista vai herdar as exceções de ${listaMae.description}.');
                          _carregar();
                        } catch (e) {
                          _snack('Erro ao definir espelho: $e', erro: true);
                        }
                      },
                      child: const Text('Definir Espelho', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── BUILD PRINCIPAL ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgSuave,
      body: Column(children: [
        _topBar(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _laranja, strokeWidth: 3))
              : _politicas.isEmpty
                  ? _estadoVazio()
                  : Padding(
                      padding: const EdgeInsets.all(32),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 4, child: _listaPoliticas()),
                        const SizedBox(width: 24),
                        Expanded(flex: 6, child: _detalhe()),
                      ]),
                    ),
        ),
      ]),
    );
  }

  Widget _topBar() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x04000000), blurRadius: 15, offset: Offset(0, 4))],
      ),
      child: Row(children: [
        const Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Políticas de Precificação', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _slate900, letterSpacing: -0.5)),
          Text('Margens, exceções e espelhos por lista de preço', style: TextStyle(fontSize: 12, color: _slate600, fontWeight: FontWeight.w500)),
        ]),
        const Spacer(),
        IconButton(icon: const Icon(Icons.sync_rounded, color: _slate600), tooltip: 'Sincronizar', onPressed: _carregar, style: IconButton.styleFrom(hoverColor: _slate100)),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
          label: const Text('Nova Política'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _laranja, foregroundColor: Colors.white, elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => _abrirFormulario(),
        ),
      ]),
    );
  }

  Widget _listaPoliticas() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Políticas Ativas', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _slate900)),
        ),
        const Divider(height: 1, color: _slate100),
        Expanded(
          child: ListView.separated(
            itemCount: _politicas.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: _slate100),
            itemBuilder: (_, i) {
              final p = _politicas[i];
              final ativa = _selecionada?.id == p.id;
              return InkWell(
                onTap: () => setState(() => _selecionada = p),
                hoverColor: _bgSuave,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  decoration: BoxDecoration(
                    color: ativa ? _laranja.withOpacity(0.02) : Colors.transparent,
                    border: Border(left: BorderSide(color: ativa ? _laranja : Colors.transparent, width: 4)),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, style: TextStyle(fontSize: 14, fontWeight: ativa ? FontWeight.w800 : FontWeight.w600, color: ativa ? _laranja : _slate900)),
                      const SizedBox(height: 8),
                      Row(children: [
                        _pill('Flat: ${p.margemFlatFormatada}', _verdeLight, _verde),
                        const SizedBox(width: 8),
                        _pill('Oferta: ${p.margemOfertaFormatada}', const Color(0xFFFFF7ED), const Color(0xFFC2410C)),
                        const SizedBox(width: 8),
                        _pill('${p.listas.length} lista(s)', _slate100, _slate600),
                      ]),
                    ])),
                    if (ativa) ...[
                      IconButton(icon: const Icon(Icons.mode_edit_outline_rounded, size: 18, color: _slate600), onPressed: () => _abrirFormulario(politica: p), style: IconButton.styleFrom(hoverColor: _slate100)),
                      IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 18, color: _vermelho), onPressed: () => _confirmarExclusao(p), style: IconButton.styleFrom(hoverColor: const Color(0xFFFEE2E2))),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _detalhe() {
    if (_selecionada == null) {
      return Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2)),
        child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: _bgSuave, shape: BoxShape.circle), child: Icon(Icons.gavel_rounded, size: 40, color: Colors.grey.shade300)),
          const SizedBox(height: 16),
          const Text('Selecione uma política para ver detalhes', style: TextStyle(color: _slate600, fontSize: 13, fontWeight: FontWeight.w500)),
        ])),
      );
    }

    final p = _selecionada!;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header da política
        Padding(
          padding: const EdgeInsets.all(28),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _slate900, letterSpacing: -0.5)),
              if (p.descricao != null) ...[
                const SizedBox(height: 6),
                Text(p.descricao!, style: const TextStyle(color: _slate600, fontSize: 13, height: 1.4)),
              ],
            ])),
            Container(
              decoration: BoxDecoration(border: Border.all(color: _slate100), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _abrirFormulario(politica: p), tooltip: 'Editar'),
                IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: _vermelho), onPressed: () => _confirmarExclusao(p), tooltip: 'Excluir'),
              ]),
            ),
          ]),
        ),

        // Cards de margem
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(children: [
            _cardMargem(label: 'Margem Flat (base)', valor: p.margemFlatFormatada, meta: 'Venda padrão', gradiente: const [Color(0xFF0F766E), Color(0xFF115E59)], icon: Icons.shield_outlined),
            const SizedBox(width: 16),
            _cardMargem(label: 'Margem Oferta (base)', valor: p.margemOfertaFormatada, meta: 'Mínimo promocional', gradiente: const [Color(0xFFC2410C), Color(0xFF9A3412)], icon: Icons.bolt_rounded),
          ]),
        ),

        const SizedBox(height: 28),

        // Título das listas
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(children: [
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tabelas de Preço Vinculadas', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _slate900)),
              Text('Clique em ⚡ para exceção ou 🔁 para espelho', style: TextStyle(fontSize: 11, color: _slate600)),
            ]),
            const Spacer(),
            OutlinedButton.icon(
              icon: const Icon(Icons.add_link_rounded, size: 16),
              label: const Text('Vincular Lista'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _laranja, side: const BorderSide(color: _laranja, width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _abrirVincularLista(p),
            ),
          ]),
        ),

        const SizedBox(height: 16),
        const Divider(height: 1, color: _slate100),

        // Lista de listas vinculadas
        Expanded(
          child: p.listas.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.link_off_rounded, size: 32, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Text('Nenhuma lista vinculada', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                ]))
              : ListView.builder(
                  itemCount: p.listas.length,
                  padding: const EdgeInsets.all(20),
                  itemBuilder: (_, i) => _cartaoLista(p.listas[i], p),
                ),
        ),
      ]),
    );
  }

  // ── Cartão de lista vinculada ─────────────────────────────────────────────

  Widget _cartaoLista(PolicyPriceList l, PricingPolicy politica) {
    final ehEspelhoFilha = l.ehEspelho;
    final temEspelhos    = l.temEspelhos;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: ehEspelhoFilha ? _laranja.withOpacity(0.03) : _bgSuave,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ehEspelhoFilha
              ? _laranja.withOpacity(0.25)
              : l.temExcecao
                  ? _roxo.withOpacity(0.25)
                  : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      child: Column(children: [
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Icon(
              ehEspelhoFilha ? Icons.copy_all_rounded : Icons.grid_view_rounded,
              size: 16,
              color: ehEspelhoFilha ? _laranja : _slate600,
            ),
          ),
          title: Row(children: [
            Expanded(child: Text(l.description, style: const TextStyle(fontWeight: FontWeight.w700, color: _slate900, fontSize: 13))),
            if (ehEspelhoFilha)
              _pill('espelho de ${l.mirrorOfPltyp}', _laranja.withOpacity(0.1), _laranja),
            if (temEspelhos) ...[
              const SizedBox(width: 6),
              _pill('${l.mirrorFilhas.length} espelho(s)', _laranja.withOpacity(0.1), _laranja),
            ],
            if (l.temExcecao) ...[
              const SizedBox(width: 6),
              _pill('exceção ativa', _roxoLight, _roxo),
            ],
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Text('ID: ${l.id}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: _slate600)),
              if (l.temExcecao) ...[
                const SizedBox(width: 12),
                // Margem efetiva
                Text(
                  'Flat efetivo: ${_fmtPct((politica.margemFlat ?? 0) + (l.excecaoFlatPct ?? 0))}  ·  Oferta efetiva: ${_fmtPct((politica.margemOferta ?? 0) + (l.excecaoOfertaPct ?? 0))}',
                  style: const TextStyle(fontSize: 11, color: _roxo, fontWeight: FontWeight.w600),
                ),
              ],
            ]),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            // Botão exceção (só em listas mãe ou sem espelho)
            if (!ehEspelhoFilha)
              Tooltip(
                message: 'Definir exceção de margem',
                child: IconButton(
                  icon: Icon(Icons.tune_rounded, size: 18, color: l.temExcecao ? _roxo : _slate600),
                  onPressed: () => _abrirExcecao(l, politica),
                  style: IconButton.styleFrom(hoverColor: _roxoLight),
                ),
              ),
            // Botão espelho (só em listas mãe)
            if (!ehEspelhoFilha)
              Tooltip(
                message: 'Adicionar lista espelho',
                child: IconButton(
                  icon: Icon(Icons.copy_all_rounded, size: 18, color: temEspelhos ? _laranja : _slate600),
                  onPressed: () => _abrirDefinirEspelho(l, politica),
                  style: IconButton.styleFrom(hoverColor: _laranja.withOpacity(0.08)),
                ),
              ),
            // Remover espelho (só em filhas)
            if (ehEspelhoFilha)
              Tooltip(
                message: 'Remover espelho',
                child: IconButton(
                  icon: const Icon(Icons.link_off_rounded, size: 18, color: _laranja),
                  onPressed: () async {
                    try {
                      await _service.removerEspelho(l.id);
                      _snack('Espelho removido. A lista mantém a última exceção.');
                      _carregar();
                    } catch (e) {
                      _snack('Erro: $e', erro: true);
                    }
                  },
                  style: IconButton.styleFrom(hoverColor: _laranja.withOpacity(0.08)),
                ),
              ),
            // Desvincular
            Tooltip(
              message: 'Desvincular da política',
              child: IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: _slate600),
                onPressed: () async {
                  try {
                    await _service.desvincularLista(l.id);
                    _snack('Lista desvinculada.');
                    _carregar();
                  } catch (e) {
                    _snack('Erro: $e', erro: true);
                  }
                },
                style: IconButton.styleFrom(hoverColor: const Color(0xFFFEE2E2)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  double? _parsePercent(String v) {
    final n = double.tryParse(v.replaceAll('%', '').replaceAll(',', '.').trim());
    return n != null ? n / 100 : null;
  }

  String _fmtPct(double? v) {
    if (v == null) return '—';
    return '${(v * 100).toStringAsFixed(1)}%';
  }

  static Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(30)),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _campoPremium({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool textoSimples = false,
    String? suffixText,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _slate900)),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        keyboardType: textoSimples ? TextInputType.text : const TextInputType.numberWithOptions(decimal: true, signed: true),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900),
        decoration: InputDecoration(
          hintText: hint,
          suffixText: suffixText,
          suffixStyle: const TextStyle(fontWeight: FontWeight.w700, color: _laranja),
          prefixIcon: Icon(icon, size: 18, color: _slate600),
          hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w400),
          filled: true,
          fillColor: _bgSuave,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _laranja, width: 1.5)),
        ),
      ),
    ]);
  }

  Widget _cardMargem({required String label, required String valor, required String meta, required List<Color> gradiente, required IconData icon}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradiente, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: gradiente.first.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w600)),
            Icon(icon, color: Colors.white.withOpacity(0.4), size: 18),
          ]),
          const SizedBox(height: 8),
          Text(valor, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)),
          const SizedBox(height: 4),
          Text(meta, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  Widget _estadoVazio() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.policy_outlined, size: 64, color: Colors.grey.shade300),
      const SizedBox(height: 16),
      const Text('Nenhuma política cadastrada', style: TextStyle(color: _slate600, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Criar Primeira Política'),
        style: ElevatedButton.styleFrom(backgroundColor: _laranja, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        onPressed: () => _abrirFormulario(),
      ),
    ]));
  }
}