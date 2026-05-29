import 'package:flutter/material.dart';
import 'package:pole_price/models/pricing_policy_model.dart';
import 'package:pole_price/service/pricing_policy_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/sidebar.dart';

class PoliticasScreen extends StatefulWidget {
  const PoliticasScreen({super.key});

  @override
  State<PoliticasScreen> createState() => _PoliticasScreenState();
}

class _PoliticasScreenState extends State<PoliticasScreen> {
  static const _laranja = Color(0xFFFF6B00);

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
        // mantém seleção se ainda existir
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
      content: Text(msg),
      backgroundColor: erro ? Colors.red : Colors.green,
    ));
  }

  // ── Abre o dialog de edição ────────────────────────────────────────
  Future<void> _abrirEdicao(PricingPolicy p) async {
    final flatCtrl = TextEditingController(
      text: p.margemFlat != null
          ? (p.margemFlat! * 100).toStringAsFixed(0)
          : '',
    );
    final ofertaCtrl = TextEditingController(
      text: p.margemOferta != null
          ? (p.margemOferta! * 100).toStringAsFixed(0)
          : '',
    );
    final descCtrl = TextEditingController(text: p.descricao ?? '');

    final salvo = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Editar: ${p.name}'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _campo(flatCtrl, 'Margem Flat (%)', hint: 'Ex: 30'),
              const SizedBox(height: 12),
              _campo(ofertaCtrl, 'Margem Oferta (%)', hint: 'Ex: 25'),
              const SizedBox(height: 12),
              _campo(descCtrl, 'Observação (opcional)', hint: 'Texto livre'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _laranja),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (salvo != true) return;

    try {
      await _service.updatePolicy(
        id: p.id,
        margemFlat: _parsePercent(flatCtrl.text),
        margemOferta: _parsePercent(ofertaCtrl.text),
        descricao: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      );
      _snack('Política atualizada com sucesso!');
      _carregar();
    } catch (e) {
      _snack('Erro ao salvar: $e', erro: true);
    }
  }

  double? _parsePercent(String v) {
    final n = double.tryParse(v.replaceAll('%', '').trim());
    return n != null ? n / 100 : null;
  }

  TextField _campo(TextEditingController ctrl, String label,
      {String? hint}) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Row(
        children: [
          const Sidebar(paginaAtiva: 'politicas'),
          Expanded(
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _politicas.isEmpty
                          ? _vazio()
                          : Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // PAINEL ESQUERDO — lista de políticas
                                  Expanded(
                                    flex: 2,
                                    child: _listaPoliticas(),
                                  ),
                                  const SizedBox(width: 20),
                                  // PAINEL DIREITO — detalhe da política selecionada
                                  Expanded(
                                    flex: 3,
                                    child: _detalhe(),
                                  ),
                                ],
                              ),
                            ),
                ),
              ],
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
            'Políticas de Preço',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _carregar,
          ),
        ],
      ),
    );
  }

  Widget _listaPoliticas() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Políticas cadastradas',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _politicas.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16),
              itemBuilder: (_, i) {
                final p = _politicas[i];
                final ativa = _selecionada?.id == p.id;
                return InkWell(
                  onTap: () => setState(() => _selecionada = p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    color: ativa ? _laranja.withOpacity(0.07) : null,
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 36,
                          decoration: BoxDecoration(
                            color: ativa ? _laranja : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: TextStyle(
                                  fontWeight: ativa
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: ativa ? _laranja : Colors.black87,
                                ),
                              ),
                              Text(
                                '${p.listas.length} lista${p.listas.length != 1 ? 's' : ''}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),
                        // badges de margem
                        if (p.margemFlat != null)
                          _badge(p.margemFlatFormatada, Colors.green.shade50,
                              Colors.green.shade700),
                        if (p.margemOferta != null) ...[
                          const SizedBox(width: 6),
                          _badge(p.margemOfertaFormatada,
                              Colors.orange.shade50, Colors.orange.shade700),
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

  Widget _detalhe() {
    if (_selecionada == null) {
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
              Icon(Icons.policy_outlined,
                  size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                'Selecione uma política para ver os detalhes',
                style: TextStyle(color: Colors.grey.shade500),
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header do detalhe
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (p.descricao != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          p.descricao!,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Editar margens',
                  onPressed: () => _abrirEdicao(p),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Cards de margem
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _cardMargem(
                  label: 'Margem Flat',
                  valor: p.margemFlatFormatada,
                  sub: 'Mínimo para venda normal',
                  cor: Colors.green,
                ),
                const SizedBox(width: 12),
                _cardMargem(
                  label: 'Margem Oferta',
                  valor: p.margemOfertaFormatada,
                  sub: 'Mínimo em promoção',
                  cor: Colors.orange,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Listas vinculadas',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),

          // Lista de price_lists vinculadas
          Expanded(
            child: p.listas.isEmpty
                ? Center(
                    child: Text(
                      'Nenhuma lista vinculada',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: p.listas.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16),
                    itemBuilder: (_, i) {
                      final l = p.listas[i];
                      return ListTile(
                        dense: true,
                        leading: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _laranja.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              l.id,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _laranja,
                              ),
                            ),
                          ),
                        ),
                        title: Text(l.description),
                        trailing: l.regraExclusiva != null
                            ? _badge(
                                l.regraExclusiva!,
                                Colors.purple.shade50,
                                Colors.purple.shade700,
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _cardMargem({
    required String label,
    required String valor,
    required String sub,
    required MaterialColor cor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cor.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cor.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    TextStyle(fontSize: 12, color: cor.shade700)),
            const SizedBox(height: 4),
            Text(
              valor,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: cor.shade800),
            ),
            const SizedBox(height: 2),
            Text(sub,
                style: TextStyle(fontSize: 11, color: cor.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _vazio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.policy_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Nenhuma política encontrada',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Execute o import_pricebook.py para importar as políticas.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );
  }
}