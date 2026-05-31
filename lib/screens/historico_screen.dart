// historico_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pole_price/screens/historico_draft_detail_screen.dart';

class HistoricoScreen extends StatefulWidget {
  const HistoricoScreen({super.key});

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen> {
  static const _laranja = Color(0xFFFF6B00);
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _registros = [];

  // Filtros
  String _filtroStatus = 'todos';
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final res = await _supabase
          .from('price_drafts')
          .select(
            'id, status, created_at, created_by_email, '
            'reviewed_by_email, reviewed_at, '
            'price_lists!master_list_id(description)',
          )
          .order('created_at', ascending: false);

      setState(() {
        _registros = (res as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar histórico: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _registrosFiltrados {
    return _registros.where((r) {
      if (_filtroStatus != 'todos' && r['status'] != _filtroStatus) {
        return false;
      }
      if (_busca.isNotEmpty) {
        final q = _busca.toLowerCase();
        final lista = r['price_lists'] as Map<String, dynamic>?;
        final nome = lista?['description']?.toString().toLowerCase() ?? '';
        final criador = r['created_by_email']?.toString().toLowerCase() ?? '';
        final revisor = r['reviewed_by_email']?.toString().toLowerCase() ?? '';
        if (!nome.contains(q) && !criador.contains(q) && !revisor.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  // ── Formatação de data ────────────────────────────────────────────────────
  // O banco salva em UTC. Fazemos parse como UTC explícito e convertemos para local.
  String _fmtData(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      // Garante interpretação como UTC mesmo que a string não tenha sufixo 'Z'
      final raw = DateTime.parse(iso);
      final dt = raw.isUtc
          ? raw.toLocal()
          : DateTime.utc(
              raw.year,
              raw.month,
              raw.day,
              raw.hour,
              raw.minute,
              raw.second,
            ).toLocal();
      final d = dt.day.toString().padLeft(2, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final mi = dt.minute.toString().padLeft(2, '0');
      return '$d/$mo/${dt.year}  $h:$mi';
    } catch (_) {
      return iso.length >= 10 ? iso.substring(0, 10) : iso;
    }
  }

  // ── Status config ─────────────────────────────────────────────────────────
  (String label, Color bg, Color fg) _statusConfig(String status) {
    return switch (status) {
      'approved' => ('Aprovado', Colors.green.shade50, Colors.green.shade700),
      'rejected' => ('Rejeitado', Colors.red.shade50, Colors.red.shade700),
      _ => ('Pendente', _laranja.withOpacity(0.10), _laranja),
    };
  }

  // ── Navega para detalhe do draft ──────────────────────────────────────────
  void _abrirDetalhe(Map<String, dynamic> r) {
    final priceList = r['price_lists'] as Map<String, dynamic>?;
    final nomeLista = priceList?['description']?.toString() ?? '—';
    final status = r['status']?.toString() ?? 'pending';
    final createdByEmail = r['created_by_email']?.toString();
    final reviewedByEmail = r['reviewed_by_email']?.toString();
    final createdAt = _fmtData(r['created_at']?.toString());
    final reviewedAt = _fmtData(r['reviewed_at']?.toString());

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HistoricoDraftDetailScreen(
          draftId: r['id'].toString(),
          nomeLista: nomeLista,
          status: status,
          createdByEmail: createdByEmail,
          reviewedByEmail: reviewedByEmail,
          createdAt: createdAt,
          reviewedAt: reviewedAt,
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Column(
        children: [
          // Topbar
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                const Text(
                  'Histórico',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Atualizar',
                  onPressed: _carregar,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),

          // Corpo
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _barraFiltros(),
                      Expanded(child: _tabela()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Barra de filtros ──────────────────────────────────────────────────────
  Widget _barraFiltros() {
    final tabs = [
      ('todos', 'Todos', _registros.length),
      (
        'pending',
        'Pendentes',
        _registros.where((r) => r['status'] == 'pending').length,
      ),
      (
        'approved',
        'Aprovados',
        _registros.where((r) => r['status'] == 'approved').length,
      ),
      (
        'rejected',
        'Rejeitados',
        _registros.where((r) => r['status'] == 'rejected').length,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          ...tabs.map((t) {
            final active = _filtroStatus == t.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text('${t.$2} (${t.$3})'),
                selected: active,
                onSelected: (_) => setState(() => _filtroStatus = t.$1),
                selectedColor: _laranja.withOpacity(0.12),
                checkmarkColor: _laranja,
                showCheckmark: false,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? _laranja : Colors.grey.shade700,
                ),
                side: BorderSide(
                  color: active
                      ? _laranja.withOpacity(0.4)
                      : Colors.grey.shade300,
                ),
              ),
            );
          }),
          const Spacer(),
          SizedBox(
            width: 280,
            height: 38,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar tabela, criador ou aprovador...',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => setState(() => _busca = v),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tabela ────────────────────────────────────────────────────────────────
  Widget _tabela() {
    final lista = _registrosFiltrados;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Cabeçalho
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: Colors.grey.shade50,
              child: Row(
                children: [
                  _th('Tabela de preços', flex: 4),
                  _th('Status', flex: 2, align: TextAlign.center),
                  _th('Criado por', flex: 3),
                  _th('Criado em', flex: 3),
                  _th('Revisado por', flex: 3),
                  _th('Revisado em', flex: 3),
                  const SizedBox(width: 32), // espaço do ícone chevron
                ],
              ),
            ),
            const Divider(height: 1),

            // Linhas
            Expanded(
              child: lista.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.history,
                            size: 48,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhum registro encontrado.',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: lista.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: Colors.grey.shade100),
                      itemBuilder: (_, i) => _linha(lista[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linha(Map<String, dynamic> r) {
    final priceList = r['price_lists'] as Map<String, dynamic>?;
    final nomeLista = priceList?['description'] ?? '—';
    final status = r['status']?.toString() ?? 'pending';
    final (label, bg, fg) = _statusConfig(status);

    return InkWell(
      onTap: () => _abrirDetalhe(r),
      hoverColor: _laranja.withOpacity(0.03),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // Tabela
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _laranja.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: _laranja,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      nomeLista,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Status badge
            Expanded(
              flex: 2,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
              ),
            ),

            // Criado por
            Expanded(
              flex: 3,
              child: _emailCell(r['created_by_email']?.toString()),
            ),

            // Criado em
            Expanded(
              flex: 3,
              child: Text(
                _fmtData(r['created_at']?.toString()),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),

            // Revisado por
            Expanded(
              flex: 3,
              child: _emailCell(r['reviewed_by_email']?.toString()),
            ),

            // Revisado em
            Expanded(
              flex: 3,
              child: Text(
                _fmtData(r['reviewed_at']?.toString()),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),

            // Chevron
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }

  Widget _emailCell(String? email) {
    if (email == null || email.isEmpty || email == 'desconhecido') {
      return Text(
        '—',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
      );
    }
    final inicial = email[0].toUpperCase();
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: _laranja.withOpacity(0.12),
          child: Text(
            inicial,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _laranja,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            email,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _th(
    String label, {
    required int flex,
    TextAlign align = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}
