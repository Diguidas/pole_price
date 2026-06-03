// rascunhos_screen.dart
import 'package:flutter/material.dart';
import 'package:pole_price/widgets/app_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RascunhosScreen extends StatefulWidget {
  const RascunhosScreen({super.key});

  @override
  State<RascunhosScreen> createState() => _RascunhosScreenState();
}

class _RascunhosScreenState extends State<RascunhosScreen> {
  static const _laranja = Color(0xFFFF6B00);

  bool _loading = true;
  List<_RascunhoItem> _rascunhos = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final userEmail =
          Supabase.instance.client.auth.currentUser?.email ?? '';

      final response = await Supabase.instance.client
          .from('price_drafts')
          .select(
            'id, status, created_at, master_list_id, created_by_email, justificativa',
          )
          .eq('status', 'draft')
          .eq('created_by_email', userEmail)
          .order('created_at', ascending: false);

      final drafts = response as List;

      // Busca nomes das listas
      final pltyps = drafts
          .map((d) => d['master_list_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      final Map<String, String> nomePorPltyp = {};
      if (pltyps.isNotEmpty) {
        final listasRes = await Supabase.instance.client
            .from('price_lists')
            .select('pltyp, ptext')
            .inFilter('pltyp', pltyps);
        for (final l in listasRes as List) {
          nomePorPltyp[l['pltyp'].toString()] = l['ptext']?.toString() ?? '';
        }
      }

      // Busca contagem de itens por draft
      final ids = drafts.map((d) => d['id'].toString()).toList();
      final Map<String, int> itensPorDraft = {};
      if (ids.isNotEmpty) {
        final itensRes = await Supabase.instance.client
            .from('price_draft_items')
            .select('draft_id')
            .inFilter('draft_id', ids);
        for (final i in itensRes as List) {
          final did = i['draft_id'].toString();
          itensPorDraft[did] = (itensPorDraft[did] ?? 0) + 1;
        }
      }

      final lista = drafts.map((j) {
        final pltyp = j['master_list_id']?.toString() ?? '';
        return _RascunhoItem(
          id: j['id'].toString(),
          listaNome: nomePorPltyp[pltyp] ?? pltyp,
          pltyp: pltyp,
          createdAt: j['created_at']?.toString() ?? '',
          justificativa: j['justificativa']?.toString(),
          totalItens: itensPorDraft[j['id'].toString()] ?? 0,
        );
      }).toList();

      setState(() => _rascunhos = lista);
    } catch (e) {
      _snack('Erro ao carregar rascunhos: $e', Colors.red);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _excluir(_RascunhoItem item) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir rascunho'),
        content: Text(
          'Tem certeza que deseja excluir o rascunho "${item.listaNome}"? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      // Exclui itens e depois o draft (respeitando FK)
      await Supabase.instance.client
          .from('price_draft_items')
          .delete()
          .eq('draft_id', item.id);
      await Supabase.instance.client
          .from('price_draft_targets')
          .delete()
          .eq('draft_id', item.id);
      await Supabase.instance.client
          .from('price_draft_exceptions')
          .delete()
          .eq('draft_id', item.id);
      await Supabase.instance.client
          .from('price_drafts')
          .delete()
          .eq('id', item.id);

      _snack('Rascunho excluído.', Colors.orange);
      await _carregar();
    } catch (e) {
      _snack('Erro ao excluir: $e', Colors.red);
    }
  }

  void _editar(_RascunhoItem item) {
    // Navega para a tela de preços passando o draftId para retomar a sessão
    AppShell.of(context).goTo(AppPage.precos, draftId: item.id);
  }

  void _snack(String msg, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: cor),
    );
  }

  String _formatarData(String raw) {
    if (raw.length >= 10) {
      final parts = raw.substring(0, 10).split('-');
      if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Cabeçalho ──────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Meus Rascunhos',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Edições salvas que ainda não foram enviadas para aprovação',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: _carregar,
                  icon: Icon(Icons.refresh, color: Colors.grey.shade600),
                  tooltip: 'Atualizar',
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Conteúdo ──────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rascunhos.isEmpty
                ? _EstadoVazio()
                : ListView.separated(
                    padding: const EdgeInsets.all(24),
                    itemCount: _rascunhos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _RascunhoCard(
                      item: _rascunhos[i],
                      formatarData: _formatarData,
                      onEditar: () => _editar(_rascunhos[i]),
                      onExcluir: () => _excluir(_rascunhos[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Card de rascunho ──────────────────────────────────────────────────────────
class _RascunhoCard extends StatelessWidget {
  static const _laranja = Color(0xFFFF6B00);
  final _RascunhoItem item;
  final String Function(String) formatarData;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;

  const _RascunhoCard({
    required this.item,
    required this.formatarData,
    required this.onEditar,
    required this.onExcluir,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Ícone
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _laranja.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.description_outlined, color: _laranja, size: 22),
          ),
          const SizedBox(width: 16),

          // Informações
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.listaNome.isNotEmpty ? item.listaNome : item.pltyp,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    _meta(
                      Icons.calendar_today_outlined,
                      'Criado em ${formatarData(item.createdAt)}',
                    ),
                    _meta(
                      Icons.inventory_2_outlined,
                      '${item.totalItens} material${item.totalItens != 1 ? 'is' : ''}',
                    ),
                    if (item.pltyp.isNotEmpty)
                      _meta(Icons.label_outline, 'Lista ${item.pltyp}'),
                  ],
                ),
                if (item.justificativa != null &&
                    item.justificativa!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.justificativa!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Badge status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Rascunho',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade700,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Ações
          IconButton(
            onPressed: onEditar,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Continuar editando',
            color: Colors.grey.shade600,
          ),
          IconButton(
            onPressed: onExcluir,
            icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
            tooltip: 'Excluir rascunho',
          ),
        ],
      ),
    );
  }

  static Widget _meta(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey.shade400),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

// ── Estado vazio ──────────────────────────────────────────────────────────────
class _EstadoVazio extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Nenhum rascunho salvo',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use "Salvar rascunho" na tela de preços para guardar seu trabalho.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────
class _RascunhoItem {
  final String id;
  final String listaNome;
  final String pltyp;
  final String createdAt;
  final String? justificativa;
  final int totalItens;

  _RascunhoItem({
    required this.id,
    required this.listaNome,
    required this.pltyp,
    required this.createdAt,
    required this.justificativa,
    required this.totalItens,
  });
}