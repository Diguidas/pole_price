// lib/screens/precos_rota.dart
//
// Rota /precos. Os parâmetros da consulta ficam na própria URL, então o F5, o
// botão voltar e links compartilhados funcionam:
//   /precos?modo=lista&pltyp=XX&datab=...   → nova consulta no SAP
//   /precos?draft=<id>                      → reabre um rascunho
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/screens/preco_screen.dart';
import 'package:pole_price/widgets/app_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Parâmetros de uma consulta de preços (lista/grupo SAP + vigência).
class PrecoParams {
  final SapModo modo;
  final String pltyp;
  final String? kdgrp;
  final DateTime? datab;
  final DateTime? datbi;
  final String? databOp;
  final String? datbiOp;

  const PrecoParams({
    required this.modo,
    required this.pltyp,
    this.kdgrp,
    this.datab,
    this.datbi,
    this.databOp,
    this.datbiOp,
  });

  /// Query string da rota /precos.
  Map<String, String> toQuery() => {
        'modo': modo.name,
        'pltyp': pltyp,
        if (kdgrp != null && kdgrp!.isNotEmpty) 'kdgrp': kdgrp!,
        if (datab != null) 'datab': datab!.toIso8601String(),
        if (datbi != null) 'datbi': datbi!.toIso8601String(),
        if (databOp != null) 'databOp': databOp!,
        if (datbiOp != null) 'datbiOp': datbiOp!,
      };

  String get location =>
      Uri(path: '/precos', queryParameters: toQuery()).toString();

  static PrecoParams? fromQuery(Map<String, String> q) {
    final pltyp = q['pltyp'];
    if (pltyp == null || pltyp.isEmpty) return null;
    return PrecoParams(
      modo: q['modo'] == 'grupo' ? SapModo.grupo : SapModo.lista,
      pltyp: pltyp,
      kdgrp: q['kdgrp'],
      datab: DateTime.tryParse(q['datab'] ?? ''),
      datbi: DateTime.tryParse(q['datbi'] ?? ''),
      databOp: q['databOp'],
      datbiOp: q['datbiOp'],
    );
  }
}

class PrecosRota extends StatefulWidget {
  final String? draftId;
  final PrecoParams? params;
  const PrecosRota({super.key, this.draftId, this.params});

  @override
  State<PrecosRota> createState() => _PrecosRotaState();
}

class _PrecosRotaState extends State<PrecosRota> {
  bool _pronto = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preparar());
  }

  Future<void> _preparar() async {
    final ctrl = PrecoController.instance;
    try {
      await ctrl.init(); // popula ctrl.listas (tem guard interno)
      if (!mounted) return;

      if (widget.draftId != null) {
        await _prepararRascunho(ctrl, widget.draftId!);
      } else if (widget.params != null) {
        _aplicarParams(ctrl, widget.params!);
      } else {
        // /precos sem parâmetros (ex.: URL digitada): pede a lista/grupo.
        final ok = await AppShell.of(context).goToPrecos();
        if (!ok && mounted) context.go('/');
        return; // se confirmou, a navegação troca esta rota
      }
    } catch (e) {
      _erro = 'Não foi possível abrir a tela de preços: $e';
    }
    if (mounted) setState(() => _pronto = true);
  }

  Future<void> _prepararRascunho(PrecoController ctrl, String draftId) async {
    final supabase = Supabase.instance.client;

    final draft = await supabase
        .from('price_drafts')
        .select('master_list_id')
        .eq('id', draftId)
        .single();

    // modo e kdgrp vêm do primeiro item (não existem no cabeçalho)
    final primeiroItem = await supabase
        .from('price_draft_items')
        .select('modo, kdgrp')
        .eq('draft_id', draftId)
        .limit(1)
        .maybeSingle();

    final pltyp = draft['master_list_id']?.toString();
    final modoStr = primeiroItem?['modo']?.toString();

    ctrl.modo = modoStr == 'grupo' ? SapModo.grupo : SapModo.lista;
    ctrl.pltyp = pltyp;
    ctrl.kdgrp = primeiroItem?['kdgrp']?.toString();
    ctrl.selecionada = ctrl.listas.where((l) => l.id == pltyp).firstOrNull;
    ctrl.materiais = [];
    ctrl.filtrados = [];
    ctrl.erro = null;
  }

  void _aplicarParams(PrecoController ctrl, PrecoParams params) {
    ctrl.pltyp = params.pltyp;
    ctrl.kdgrp = params.kdgrp;
    ctrl.datab = params.datab;
    ctrl.datbi = params.datbi;
    ctrl.databOp = params.databOp;
    ctrl.datbiOp = params.datbiOp;
    ctrl.modo = params.modo;
    // Consulta nova entra excluindo materiais inativos e bloqueados
    // ('E' = excluir; o usuário ajusta na tela se precisar incluir).
    ctrl.kznepFilter = 'E';
    ctrl.loevmFilter = 'E';
    ctrl.selecionada =
        ctrl.listas.where((l) => l.id == params.pltyp).firstOrNull;
    ctrl.materiais = [];
    ctrl.filtrados = [];
    ctrl.erro = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_erro != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_erro!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.go('/'),
              child: const Text('Voltar ao início'),
            ),
          ],
        ),
      );
    }
    if (!_pronto) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = widget.params;
    return PrecoScreen(
      key: ValueKey(
        widget.draftId ??
            '${p?.pltyp}_${p?.kdgrp}_${p?.datab?.millisecondsSinceEpoch}',
      ),
      draftId: widget.draftId,
    );
  }
}
