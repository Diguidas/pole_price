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
          _selecionada = lista
              .where((p) => p.id == _selecionada!.id)
              .firstOrNull;
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
        content: Text(msg),
        backgroundColor: erro ? Colors.red : Colors.green,
      ),
    );
  }

  // ── Dialog de criar / editar política ─────────────────────────────

  Future<void> _abrirFormulario({PricingPolicy? politica}) async {
    final isEdicao = politica != null;
    final idCtrl = TextEditingController(text: isEdicao ? politica.id : '');
    final nomeCtrl = TextEditingController(text: isEdicao ? politica.name : '');
    final flatCtrl = TextEditingController(
      text: politica?.margemFlat != null
          ? (politica!.margemFlat! * 100).toStringAsFixed(0)
          : '',
    );
    final ofertaCtrl = TextEditingController(
      text: politica?.margemOferta != null
          ? (politica!.margemOferta! * 100).toStringAsFixed(0)
          : '',
    );
    final descCtrl = TextEditingController(text: politica?.descricao ?? '');

    final salvo = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(isEdicao ? 'Editar política' : 'Nova política'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isEdicao) ...[
                _campo(
                  idCtrl,
                  'ID (código único)',
                  hint: 'Ex: POL-004',
                  textoSimples: true,
                ),
                const SizedBox(height: 12),
              ],
              _campo(
                nomeCtrl,
                'Nome da política',
                hint: 'Ex: Premium',
                textoSimples: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _campo(flatCtrl, 'Margem Flat (%)', hint: 'Ex: 30'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _campo(
                      ofertaCtrl,
                      'Margem Oferta (%)',
                      hint: 'Ex: 25',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _campo(
                descCtrl,
                'Observação (opcional)',
                hint: 'Texto livre',
                textoSimples: true,
              ),
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
            child: Text(
              isEdicao ? 'Salvar' : 'Criar',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
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
        _snack('Política atualizada!');
      } else {
        final id = idCtrl.text.trim();
        if (id.isEmpty) {
          _snack('O ID é obrigatório.', erro: true);
          return;
        }
        await _service.createPolicy(
          id: id,
          name: nome,
          margemFlat: _parsePercent(flatCtrl.text),
          margemOferta: _parsePercent(ofertaCtrl.text),
          descricao: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        );
        _snack('Política criada com sucesso!');
      }
      _carregar();
    } catch (e) {
      _snack('Erro ao salvar: $e', erro: true);
    }
  }

  // ── Confirmação de exclusão ────────────────────────────────────────

  Future<void> _confirmarExclusao(PricingPolicy p) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Excluir política'),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            children: [
              const TextSpan(text: 'Tem certeza que deseja excluir '),
              TextSpan(
                text: p.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const TextSpan(
                text:
                    '?\n\nAs listas vinculadas serão desvinculadas automaticamente.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      await _service.deletePolicy(p.id);
      setState(() {
        if (_selecionada?.id == p.id) _selecionada = null;
      });
      _snack('Política excluída.');
      _carregar();
    } catch (e) {
      _snack('Erro ao excluir: $e', erro: true);
    }
  }

  // ── Vincular lista ─────────────────────────────────────────────────

  Future<void> _abrirVincularLista(PricingPolicy politica) async {
    List<AllPriceList> todasListas = [];
    bool carregando = true;

    final listasSelecionadas = <String>{};

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            // Carrega na primeira renderização
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: SizedBox(
                width: 500,
                height: 480,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.playlist_add,
                            color: _laranja,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Vincular lista de preço',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  politica.name,
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
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Listas já vinculadas a outra política aparecerão marcadas. Você pode transferi-las.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),

                    Expanded(
                      child: carregando
                          ? const Center(child: CircularProgressIndicator())
                          : todasListas.isEmpty
                          ? Center(
                              child: Text(
                                'Nenhuma lista encontrada',
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: todasListas.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, indent: 16),
                              itemBuilder: (_, i) {
                                final l = todasListas[i];
                                final jaNestaPolitica = jaVinculadas.contains(
                                  l.id,
                                );
                                final emOutra =
                                    l.vinculada && l.policyId != politica.id;
                                final selecionada = listasSelecionadas.contains(
                                  l.id,
                                );

                                return CheckboxListTile(
                                  dense: true,
                                  value: jaNestaPolitica || selecionada,
                                  onChanged: jaNestaPolitica
                                      ? null
                                      : (v) => setLocal(
                                          () => v == true
                                              ? listasSelecionadas.add(l.id)
                                              : listasSelecionadas.remove(l.id),
                                        ),
                                  activeColor: _laranja,
                                  title: Text(
                                    l.description,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    l.id,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  secondary: emOutra
                                      ? Tooltip(
                                          message: 'Vinculada a: ${l.policyId}',
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: Colors.orange.shade200,
                                              ),
                                            ),
                                            child: Text(
                                              'Outra política',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.orange.shade700,
                                              ),
                                            ),
                                          ),
                                        )
                                      : jaNestaPolitica
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            'Vinculada',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.green.shade700,
                                            ),
                                          ),
                                        )
                                      : null,
                                );
                              },
                            ),
                    ),

                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                      child: Row(
                        children: [
                          Text(
                            '${listasSelecionadas.length} selecionada(s)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _laranja,
                            ),
                            onPressed: listasSelecionadas.isEmpty
                                ? null
                                : () async {
                                    Navigator.pop(ctx);
                                    int vinculadas = 0;
                                    for (final id in listasSelecionadas) {
                                      try {
                                        await _service.vincularLista(
                                          listaId: id,
                                          policyId: politica.id,
                                        );
                                        vinculadas++;
                                      } catch (e) {
                                        _snack(
                                          'Erro ao vincular $id: $e',
                                          erro: true,
                                        );
                                      }
                                    }
                                    if (vinculadas > 0) {
                                      _snack(
                                        '$vinculadas lista(s) vinculada(s)!',
                                      );
                                      _carregar();
                                    }
                                  },
                            child: const Text(
                              'Vincular',
                              style: TextStyle(color: Colors.white),
                            ),
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

  // ── Helpers ────────────────────────────────────────────────────────

  double? _parsePercent(String v) {
    final n = double.tryParse(v.replaceAll('%', '').trim());
    return n != null ? n / 100 : null;
  }

  TextField _campo(
    TextEditingController ctrl,
    String label, {
    String? hint,
    bool textoSimples = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: textoSimples
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
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
      body: Column(
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
                        Expanded(flex: 2, child: _listaPoliticas()),
                        const SizedBox(width: 20),
                        Expanded(flex: 3, child: _detalhe()),
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
            'Políticas de Preço',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _carregar,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nova política'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _laranja,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _abrirFormulario(),
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
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
              itemBuilder: (_, i) {
                final p = _politicas[i];
                final ativa = _selecionada?.id == p.id;
                return InkWell(
                  onTap: () => setState(() => _selecionada = p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    color: ativa ? _laranja.withOpacity(0.07) : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: ativa
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: ativa
                                      ? _laranja
                                      : Colors.grey.shade800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _badge(
                                    p.margemFlatFormatada,
                                    Colors.green.shade50,
                                    Colors.green.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  _badge(
                                    p.margemOfertaFormatada,
                                    Colors.orange.shade50,
                                    Colors.orange.shade700,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Ações rápidas visíveis ao hover/selecionar
                        if (ativa) ...[
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            tooltip: 'Editar',
                            color: Colors.grey.shade600,
                            onPressed: () => _abrirFormulario(politica: p),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            tooltip: 'Excluir',
                            color: Colors.red.shade400,
                            onPressed: () => _confirmarExclusao(p),
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
              Icon(
                Icons.policy_outlined,
                size: 48,
                color: Colors.grey.shade300,
              ),
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
          // Header
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
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (p.descricao != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          p.descricao!,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Editar política',
                  onPressed: () => _abrirFormulario(politica: p),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Excluir política',
                  color: Colors.red.shade400,
                  onPressed: () => _confirmarExclusao(p),
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

          // Header listas
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Listas vinculadas',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_link, size: 16),
                  label: const Text('Vincular lista'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _laranja,
                    side: const BorderSide(color: _laranja),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => _abrirVincularLista(p),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          Expanded(
            child: p.listas.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.list_outlined,
                          size: 36,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Nenhuma lista vinculada',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Clique em "Vincular lista" para adicionar',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                          ),
                        ),
                      ],
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
                        trailing: IconButton(
                          icon: Icon(
                            Icons.link_off,
                            size: 18,
                            color: Colors.grey.shade400,
                          ),
                          tooltip: 'Desvincular',
                          onPressed: () async {
                            try {
                              await _service.desvincularLista(l.id);
                              _snack('Lista desvinculada.');
                              _carregar();
                            } catch (e) {
                              _snack('Erro ao desvincular: $e', erro: true);
                            }
                          },
                        ),
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
            Text(label, style: TextStyle(fontSize: 12, color: cor.shade700)),
            const SizedBox(height: 4),
            Text(
              valor,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: cor.shade800,
              ),
            ),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(fontSize: 11, color: cor.shade600)),
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
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _vazio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.policy_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Nenhuma política encontrada',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Criar primeira política'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _laranja,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _abrirFormulario(),
          ),
        ],
      ),
    );
  }
}
