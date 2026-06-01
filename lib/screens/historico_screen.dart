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
  // Paleta de Cores Premium unificada do ecossistema
  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate400 = Color(0xFF94A3B8);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _slate100 = Color(0xFFF1F5F9);
  static const _bgSuave = Color(0xFFF8FAFC);

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
      // 1. Busca os drafts
      final res = await _supabase
          .from('price_drafts')
          .select(
            'id, status, created_at, created_by_email, '
            'reviewed_by_email, reviewed_at, master_list_id',
          )
          .order('created_at', ascending: false);

      final drafts = (res as List).cast<Map<String, dynamic>>();

      // 2. Coleta os pltyps únicos
      final pltyps = drafts
          .map((d) => d['master_list_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      // 3. Busca as descrições
      Map<String, String> descMap = {};
      if (pltyps.isNotEmpty) {
        final listas = await _supabase
            .from('price_lists')
            .select('pltyp, ptext')
            .inFilter('pltyp', pltyps);
        for (final l in listas as List) {
          descMap[l['pltyp'].toString()] = l['ptext']?.toString() ?? '';
        }
      }

      // 4. Enriquece cada draft com a descrição da lista
      setState(() {
        _registros = drafts.map((d) {
          final m = Map<String, dynamic>.from(d);
          final pltyp = m['master_list_id']?.toString();
          m['price_lists'] = {'description': descMap[pltyp] ?? pltyp ?? ''};
          return m;
        }).toList();
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

  String _fmtData(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
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
      return '$d/$mo/${dt.year} $h:$mi';
    } catch (_) {
      return iso.length >= 10 ? iso.substring(0, 10) : iso;
    }
  }

  (String label, Color bg, Color fg) _statusConfig(String status) {
    return switch (status) {
      'approved' => (
        'Aprovado',
        const Color(0xFFECFDF5),
        const Color(0xFF047857),
      ),
      'rejected' => (
        'Rejeitado',
        const Color(0xFFFFF1F2),
        const Color(0xFFB91C1C),
      ),
      _ => ('Pendente', const Color(0xFFFFF7ED), const Color(0xFFC2410C)),
    };
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgSuave,
      body: Column(
        children: [
          _topBarPremium(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _laranja),
                  )
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

  Widget _topBarPremium() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x02000000),
            blurRadius: 15,
            offset: Offset(0, 4),
          ),
        ],
        border: Border(bottom: BorderSide(color: _slate100)),
      ),
      child: Row(
        children: [
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Histórico de Alterações',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _slate900,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                'Auditoria completa de rascunhos, submissões e decisões comerciais anteriores',
                style: TextStyle(
                  fontSize: 12,
                  color: _slate600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Atualizar Histórico',
            onPressed: _carregar,
            color: _slate600,
            style: IconButton.styleFrom(
              hoverColor: _slate100,
              padding: const EdgeInsets.all(10),
            ),
          ),
        ],
      ),
    );
  }

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
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
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
                selectedColor: _laranja.withOpacity(0.08),
                checkmarkColor: _laranja,
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? _laranja : _slate600,
                ),
                side: BorderSide(
                  color: active ? _laranja.withOpacity(0.5) : _slate200,
                  width: active ? 1.5 : 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }),
          const Spacer(),
          SizedBox(
            width: 320,
            height: 40,
            child: TextField(
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Buscar tabela, criador ou auditor...',
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: _slate400,
                  fontWeight: FontWeight.w500,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: _slate600,
                ),
                isDense: true,
                filled: true,
                fillColor: _bgSuave,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _slate200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _laranja, width: 1.5),
                ),
              ),
              onChanged: (v) => setState(() => _busca = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabela() {
    final lista = _registrosFiltrados;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _slate200),
          boxShadow: const [
            BoxShadow(
              color: Color(0x01000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              color: _bgSuave,
              child: Row(
                children: [
                  _th('Estrutura Comercial / Tabela', flex: 4),
                  _th('Status', flex: 2, align: TextAlign.center),
                  _th('Criado por', flex: 3),
                  _th('Solicitação em', flex: 3),
                  _th('Auditado por', flex: 3),
                  _th('Efetivado em', flex: 3),
                  const SizedBox(width: 32),
                ],
              ),
            ),
            const Divider(height: 1, color: _slate100),
            Expanded(
              child: lista.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              color: _bgSuave,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.history_toggle_off_rounded,
                              size: 40,
                              color: _slate400,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Nenhum registro localizado.',
                            style: TextStyle(
                              color: _slate900,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Refine ou altere os filtros superiores.',
                            style: TextStyle(color: _slate600, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: lista.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: _slate100),
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
      hoverColor: _laranja.withOpacity(0.02),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      nomeLista,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _slate900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: fg,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: _emailCell(r['created_by_email']?.toString()),
            ),
            Expanded(
              flex: 3,
              child: Text(
                _fmtData(r['created_at']?.toString()),
                style: const TextStyle(
                  fontSize: 12,
                  color: _slate600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: _emailCell(r['reviewed_by_email']?.toString()),
            ),
            Expanded(
              flex: 3,
              child: Text(
                _fmtData(r['reviewed_at']?.toString()),
                style: const TextStyle(
                  fontSize: 12,
                  color: _slate600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: _slate400),
          ],
        ),
      ),
    );
  }

  Widget _emailCell(String? email) {
    if (email == null || email.isEmpty || email == 'desconhecido') {
      return const Text(
        '—',
        style: TextStyle(
          fontSize: 12,
          color: _slate400,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    final inicial = email[0].toUpperCase();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: _laranja.withOpacity(0.08),
          child: Text(
            inicial,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: _laranja,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            email,
            style: const TextStyle(
              fontSize: 12,
              color: _slate600,
              fontWeight: FontWeight.w500,
            ),
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
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: _slate600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
