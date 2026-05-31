// lib/screens/politicas_screen.dart

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
  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate100 = Color(0xFFF1F5F9);
  static const _bgSuave = Color(0xFFF8FAFC);

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              erro ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: erro ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      ),
    );
  }

  // ── FORMULÁRIO ANIMADO PREMIUM (Criação e Edição sem ID Manual) ──

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
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final scale = Tween<double>(begin: 0.92, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeInOutBack),
        );
        final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(animation);

        return Opacity(
          opacity: opacity.value,
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
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _slate100)),
                ),
                child: Row(
                  children: [
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
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _slate900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _campoPremium(
                        controller: nomeCtrl,
                        label: 'Nome Comercial da Política',
                        hint: 'Ex: Varejo Sul / Distribuidor High',
                        icon: Icons.label_important_outline_rounded,
                        textoSimples: true,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _campoPremium(
                              controller: flatCtrl,
                              label: 'Margem Flat',
                              hint: '30%',
                              icon: Icons.trending_up_rounded,
                              suffixText: '%',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _campoPremium(
                              controller: ofertaCtrl,
                              label: 'Margem Oferta',
                              hint: '25%',
                              icon: Icons.local_offer_outlined,
                              suffixText: '%',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _campoPremium(
                        controller: descCtrl,
                        label: 'Descrição / Observações Estratégicas',
                        hint: 'Informe o objetivo dessa regra...',
                        icon: Icons.description_outlined,
                        textoSimples: true,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    foregroundColor: _slate600,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _laranja,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    isEdicao ? 'Salvar Alterações' : 'Criar Política',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (salvo != true) return;

    final nome = nomeCtrl.text.trim();
    if (nome.isEmpty) {
      _snack('O nome da política é obrigatório.', erro: true);
      return;
    }

    try {
      if (isEdicao) {
        await _service.updatePolicy(
          id: politica.id,
          name: nome,
          margemFlat: _parsePercent(flatCtrl.text),
          margemOferta: _parsePercent(ofertaCtrl.text),
          descricao: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        );
        _snack('Política corporativa atualizada!');
      } else {
        // O ID agora não é passado no createPolicy se o seu service/banco gerar automaticamente.
        // Caso seu service exija a String ID por assinatura antiga, passamos o próprio nome tratado ou deixamos em branco se o banco resolver.
        // Ajustado para gerar uma hash/timestamp sutil caso a assinatura do service ainda exija o parâmetro obrigatoriamente.
        final idGeradoAutomatico = 'POL-${DateTime.now().millisecondsSinceEpoch}';
        
        await _service.createPolicy(
          id: idGeradoAutomatico, 
          name: nome,
          margemFlat: _parsePercent(flatCtrl.text),
          margemOferta: _parsePercent(ofertaCtrl.text),
          descricao: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        );
        _snack('Nova política inserida com sucesso no ecossistema!');
      }
      _carregar();
    } catch (e) {
      _snack('Erro ao processar requisição: $e', erro: true);
    }
  }

  // ── MODAL DE DELEÇÃO LUXUOSO ──────────────────────────────────────

  Future<void> _confirmarExclusao(PricingPolicy p) async {
    final confirmado = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ConfirmarExclusao',
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
                SizedBox(width: 12),
                Text(
                  'Atenção! Excluir Política',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _slate900),
                ),
              ],
            ),
            content: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 14, color: _slate600, height: 1.5),
                children: [
                  const TextSpan(text: 'Você está prestes a remover permanentemente a política '),
                  TextSpan(
                    text: p.name,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: _slate900),
                  ),
                  const TextSpan(
                    text: '.\n\nTodas as tabelas de preços indexadas a ela serão desvinculadas imediatamente.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Manter Política', style: TextStyle(color: _slate600, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmar Exclusão', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      },
    );

    if (confirmado != true) return;

    try {
      await _service.deletePolicy(p.id);
      setState(() {
        if (_selecionada?.id == p.id) _selecionada = null;
      });
      _snack('A política foi removida do banco de dados.', erro: true);
      _carregar();
    } catch (e) {
      _snack('Não foi possível excluir: $e', erro: true);
    }
  }

  // ── VINCULAR LISTA (Design UI Premium) ────────────────────────────

  Future<void> _abrirVincularLista(PricingPolicy politica) async {
    List<AllPriceList> todasListas = [];
    bool carregando = true;
    final listasSelecionadas = <String>{};

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            if (carregando) {
              _service.getAllPriceLists().then((listas) {
                setLocal(() {
                  todasListas = listas;
                  carregando = false;
                });
              });
            }

            final jaVinculadas = politica.listas.map((l) => l.id).toSet();

            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: SizedBox(
                width: 540,
                height: 560,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 28, 24, 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _laranja.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.link_rounded, color: _laranja, size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Acoplar Tabelas de Preço',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _slate900),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Vinculando regras à: ${politica.name}',
                                  style: const TextStyle(fontSize: 12, color: _laranja, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: _slate600),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: _slate100),
                    Expanded(
                      child: carregando
                          ? const Center(child: CircularProgressIndicator(color: _laranja))
                          : todasListas.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.folder_off_outlined, size: 40, color: Colors.grey.shade300),
                                      const SizedBox(height: 12),
                                      Text('Nenhuma lista operacional vaga', style: TextStyle(color: Colors.grey.shade400)),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: todasListas.length,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  itemBuilder: (_, i) {
                                    final l = todasListas[i];
                                    final jaNestaPolitica = jaVinculadas.contains(l.id);
                                    final emOutra = l.vinculada && l.policyId != politica.id;
                                    final selecionada = listasSelecionadas.contains(l.id);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: jaNestaPolitica
                                            ? const Color(0xFFF0FDF4)
                                            : selecionada
                                                ? _laranja.withOpacity(0.03)
                                                : Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: jaNestaPolitica
                                              ? const Color(0xFFDCFCE7)
                                              : selecionada
                                                  ? _laranja.withOpacity(0.3)
                                                  : _slate100,
                                          width: 1.2,
                                        ),
                                      ),
                                      child: CheckboxListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                        dense: true,
                                        value: jaNestaPolitica || selecionada,
                                        onChanged: jaNestaPolitica
                                            ? null
                                            : (v) => setLocal(
                                                  () => v == true ? listasSelecionadas.add(l.id) : listasSelecionadas.remove(l.id),
                                                ),
                                        activeColor: _laranja,
                                        checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                        title: Text(
                                          l.description,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _slate900),
                                        ),
                                        subtitle: Text(
                                          'ID: ${l.id}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontFamily: 'monospace'),
                                        ),
                                        secondary: emOutra
                                            ? _pillStatus('Outra Regra: ${l.policyId}', const Color(0xFFFEF3C7), const Color(0xFFD97706))
                                            : jaNestaPolitica
                                                ? _pillStatus('Vinculada', const Color(0xFFDCFCE7), const Color(0xFF16A34A))
                                                : _pillStatus('Disponível', _slate100, _slate600),
                                      ),
                                    );
                                  },
                                ),
                    ),
                    const Divider(height: 1, color: _slate100),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
                      child: Row(
                        children: [
                          Text(
                            '${listasSelecionadas.length} selecionada(s) para acoplagem',
                            style: const TextStyle(fontSize: 13, color: _slate600, fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancelar', style: TextStyle(color: _slate600)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _laranja,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: listasSelecionadas.isEmpty
                                ? null
                                : () async {
                                    Navigator.pop(ctx);
                                    int vinculadas = 0;
                                    for (final id in listasSelecionadas) {
                                      try {
                                        await _service.vincularLista(listaId: id, policyId: politica.id);
                                        vinculadas++;
                                      } catch (e) {
                                        _snack('Falha na amarração da lista $id: $e', erro: true);
                                      }
                                    }
                                    if (vinculadas > 0) {
                                      _snack('Sucesso! $vinculadas tabela(s) integrada(s) à política.');
                                      _carregar();
                                    }
                                  },
                            child: const Text('Confirmar Vínculo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── INTERFACE / BUILD PRINCIPAL ───────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgSuave,
      body: Column(
        children: [
          _topBarPremium(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _laranja, strokeWidth: 3))
                : _politicas.isEmpty
                    ? _estadoVazio()
                    : Padding(
                        padding: const EdgeInsets.all(32),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 4, child: _listaPoliticasBento()),
                            const SizedBox(width: 24),
                            Expanded(flex: 6, child: _detalheBento()),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _topBarPremium() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x02000000), blurRadius: 15, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Políticas de Precificação',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _slate900, letterSpacing: -0.5),
              ),
              Text(
                'Definições de margem corporativa e markup estratégico',
                style: TextStyle(fontSize: 12, color: _slate600, fontWeight: FontWeight.w500),
              )
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.sync_rounded, color: _slate600),
            tooltip: 'Sincronizar Banco',
            onPressed: _carregar,
            style: IconButton.styleFrom(hoverColor: _slate100),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
            label: const Text('Nova Política Corporativa'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _laranja,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _abrirFormulario(),
          ),
        ],
      ),
    );
  }

  Widget _listaPoliticasBento() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: const [BoxShadow(color: Color(0x02000000), blurRadius: 20)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Regras Ativas',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _slate900),
            ),
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
                      border: Border(
                        left: BorderSide(
                          color: ativa ? _laranja : Colors.transparent,
                          width: 4,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: ativa ? FontWeight.w800 : FontWeight.w600,
                                  color: ativa ? _laranja : _slate900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _pillStatus('Flat: ${p.margemFlatFormatada}', const Color(0xFFECFDF5), const Color(0xFF047857)),
                                  const SizedBox(width: 8),
                                  _pillStatus('Oferta: ${p.margemOfertaFormatada}', const Color(0xFFFFF7ED), const Color(0xFFC2410C)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (ativa) ...[
                          IconButton(
                            icon: const Icon(Icons.mode_edit_outline_rounded, size: 18, color: _slate600),
                            onPressed: () => _abrirFormulario(politica: p),
                            style: IconButton.styleFrom(hoverColor: _slate100),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                            onPressed: () => _confirmarExclusao(p),
                            style: IconButton.styleFrom(hoverColor: const Color(0xFFFEE2E2)),
                          ),
                        ],
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

  Widget _detalheBento() {
    if (_selecionada == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: _bgSuave, shape: BoxShape.circle),
                child: Icon(Icons.gavel_rounded, size: 40, color: Colors.grey.shade300),
              ),
              const SizedBox(height: 16),
              const Text(
                'Selecione uma diretriz estratégica\npara inspecionar amarrações e dados',
                style: TextStyle(color: _slate600, fontSize: 13, fontWeight: FontWeight.w500, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final p = _selecionada!;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: const [BoxShadow(color: Color(0x01000000), blurRadius: 24)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(28),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _slate900, letterSpacing: -0.5),
                      ),
                      if (p.descricao != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          p.descricao!,
                          style: const TextStyle(color: _slate600, fontSize: 13, height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(border: Border.all(color: _slate100), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _abrirFormulario(politica: p),
                        tooltip: 'Editar Estrutura',
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                        onPressed: () => _confirmarExclusao(p),
                        tooltip: 'Deletar Diretriz',
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              children: [
                _cardMargemPremium(
                  label: 'Margem de Segurança (Flat)',
                  valor: p.margemFlatFormatada,
                  meta: 'Target de Venda Padrão',
                  gradiente: const [Color(0xFF0F766E), Color(0xFF115E59)],
                  icon: Icons.shield_outlined,
                ),
                const SizedBox(width: 16),
                _cardMargemPremium(
                  label: 'Margem Limite (Oferta)',
                  valor: p.margemOfertaFormatada,
                  meta: 'Gatilho Mínimo Promocional',
                  gradiente: const [Color(0xFFC2410C), Color(0xFF9A3412)],
                  icon: Icons.bolt_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tabelas de Preço Indexadas', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _slate900)),
                    Text('Filiais e canais que obedecem a esta margem', style: TextStyle(fontSize: 11, color: _slate600)),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_link_rounded, size: 16),
                  label: const Text('Acoplar Tabela'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _laranja,
                    side: const BorderSide(color: _laranja, width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _abrirVincularLista(p),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: _slate100),
          Expanded(
            child: p.listas.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.link_off_rounded, size: 32, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(
                          'Nenhuma amarração ativa para esta política',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: p.listas.length,
                    padding: const EdgeInsets.all(20),
                    itemBuilder: (_, i) {
                      final l = p.listas[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: _bgSuave,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.grid_view_rounded, size: 16, color: _laranja),
                          ),
                          title: Text(l.description, style: const TextStyle(fontWeight: FontWeight.w700, color: _slate900)),
                          subtitle: Text('SKU Ref: ${l.id}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.link_off_rounded, size: 18, color: Color(0xFF94A3B8)),
                            tooltip: 'Romper Vínculo',
                            onPressed: () async {
                              try {
                                await _service.desvincularLista(l.id);
                                _snack('Acoplagem desfeita com sucesso.');
                                _carregar();
                              } catch (e) {
                                _snack('Erro ao quebrar vínculo: $e', erro: true);
                              }
                            },
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

  // ── AUXILIARES DE MICRO-INTERFACE ──────────────────────────────────

  double? _parsePercent(String v) {
    final n = double.tryParse(v.replaceAll('%', '').trim());
    return n != null ? n / 100 : null;
  }

  Widget _campoPremium({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool textoSimples = false,
    String? suffixText,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _slate900),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: textoSimples ? TextInputType.text : const TextInputType.numberWithOptions(decimal: true),
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
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _laranja, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cardMargemPremium({
    required String label,
    required String valor,
    required String meta,
    required List<Color> gradiente,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradiente, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: gradiente.first.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w600)),
                Icon(icon, color: Colors.white.withOpacity(0.4), size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              valor,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
            ),
            const SizedBox(height: 4),
            Text(meta, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  static Widget _pillStatus(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(30)),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg, letterSpacing: -0.1),
      ),
    );
  }

  Widget _estadoVazio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.policy_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'Nenhuma diretriz de margem foi cadastrada',
            style: TextStyle(color: _slate600, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Configurar Primeira Política'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _laranja,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _abrirFormulario(),
          ),
        ],
      ),
    );
  }
}