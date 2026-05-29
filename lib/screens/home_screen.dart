import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pole_price/screens/login_page.dart';
import 'package:pole_price/screens/preco_screen.dart';
import 'package:pole_price/screens/definir_aprovacoes_screen.dart';
import 'package:pole_price/widgets/sidebar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;

  int _totalPendentes = 0;
  int _totalAprovados = 0;
  int _totalRejeitados = 0;
  List<Map<String, dynamic>> _ultimosPendentes = [];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _loading = true);
    try {
      // Busca todos os drafts com nome da lista mãe
      final res = await _supabase
          .from('price_drafts')
          .select('id, status, created_at, price_lists(description)')
          .order('created_at', ascending: false);

      final todos = res as List;

      final pendentes =
          todos.where((d) => d['status'] == 'pending').toList();
      final aprovados =
          todos.where((d) => d['status'] == 'approved').toList();
      final rejeitados =
          todos.where((d) => d['status'] == 'rejected').toList();

      setState(() {
        _totalPendentes = pendentes.length;
        _totalAprovados = aprovados.length;
        _totalRejeitados = rejeitados.length;
        // Últimos 5 pendentes para o feed
        _ultimosPendentes = pendentes.take(5).cast<Map<String, dynamic>>().toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const laranja = Color(0xFFFF6B00);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Row(
        children: [
          const Sidebar(paginaAtiva: 'home'),

          Expanded(
            child: Column(
              children: [
                // ── Topbar ──────────────────────────────────────────────
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                        bottom: BorderSide(color: Colors.grey.shade100)),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Dashboard',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      // usuário simulado
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: laranja.withOpacity(0.15),
                              child: const Icon(Icons.person,
                                  size: 16, color: laranja),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'usuario@empresa.com',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.logout_outlined,
                            color: Colors.grey),
                        tooltip: 'Sair',
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LoginPage()),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Corpo ────────────────────────────────────────────────
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: _carregarDados,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Saudação
                                const Text(
                                  'Bem-vindo de volta 👋',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Aqui está o resumo de hoje.',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14),
                                ),
                                const SizedBox(height: 24),

                                // ── Cards de métricas ──────────────────
                                Row(
                                  children: [
                                    _metricCard(
                                      label: 'Pendentes',
                                      valor: _totalPendentes,
                                      icon: Icons.hourglass_top_rounded,
                                      cor: const Color(0xFFFF6B00),
                                    ),
                                    const SizedBox(width: 16),
                                    _metricCard(
                                      label: 'Aprovados',
                                      valor: _totalAprovados,
                                      icon: Icons.check_circle_outline,
                                      cor: const Color(0xFF22C55E),
                                    ),
                                    const SizedBox(width: 16),
                                    _metricCard(
                                      label: 'Rejeitados',
                                      valor: _totalRejeitados,
                                      icon: Icons.cancel_outlined,
                                      cor: const Color(0xFFEF4444),
                                    ),
                                    const SizedBox(width: 16),
                                    _metricCard(
                                      label: 'Total de drafts',
                                      valor: _totalPendentes +
                                          _totalAprovados +
                                          _totalRejeitados,
                                      icon: Icons.description_outlined,
                                      cor: const Color(0xFF6366F1),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 28),

                                // ── Linha: feed + atalhos ──────────────
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Feed de pendentes
                                    Expanded(
                                      flex: 3,
                                      child: _feedPendentes(),
                                    ),
                                    const SizedBox(width: 16),
                                    // Atalhos de módulos
                                    Expanded(
                                      flex: 2,
                                      child: _atalhos(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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

  // ── Metric card ────────────────────────────────────────────────────────
  Widget _metricCard({
    required String label,
    required int valor,
    required IconData icon,
    required Color cor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: cor, size: 22),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$valor',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: cor),
                ),
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Feed de pendentes ──────────────────────────────────────────────────
  Widget _feedPendentes() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                const Text(
                  'Rascunhos Pendentes',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.arrow_forward, size: 15),
                  label: const Text('Ver todos'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B00),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AprovacoesScreen()),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_ultimosPendentes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('Nenhum rascunho pendente no momento.',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ultimosPendentes.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 20, endIndent: 20),
              itemBuilder: (context, i) {
                final d = _ultimosPendentes[i];
                final priceList =
                    d['price_lists'] as Map<String, dynamic>?;
                final nome =
                    priceList?['description'] ?? 'Tabela desconhecida';
                final idCurto =
                    (d['id'] as String).substring(0, 8);
                final criadoEm = d['created_at'] as String? ?? '';
                final dataFormatada = criadoEm.length >= 10
                    ? criadoEm.substring(0, 10).split('-').reversed.join('/')
                    : criadoEm;

                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B00).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.description_outlined,
                        size: 18, color: Color(0xFFFF6B00)),
                  ),
                  title: Text(nome,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('ID: $idCurto...  •  $dataFormatada',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B00).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Pendente',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF6B00)),
                    ),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AprovacoesScreen()),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── Atalhos de módulos ─────────────────────────────────────────────────
  Widget _atalhos() {
    final modulos = [
      {
        'titulo': 'Gestão de Preços',
        'subtitulo': 'Editar tabelas e enviar para aprovação',
        'icon': Icons.attach_money_rounded,
        'onTap': () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrecoScreen()),
            ),
      },
      {
        'titulo': 'Aprovações',
        'subtitulo': 'Revisar e aprovar rascunhos pendentes',
        'icon': Icons.check_circle_outline_rounded,
        'onTap': () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AprovacoesScreen()),
            ),
      },
      {
        'titulo': 'Relatórios',
        'subtitulo': 'Visualizar histórico e resultados',
        'icon': Icons.bar_chart_rounded,
        'onTap': () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Em breve: Relatórios')),
            ),
      },
      {
        'titulo': 'Grupo de Materiais',
        'subtitulo': 'Gerenciar agrupamentos de produtos',
        'icon': Icons.layers_outlined,
        'onTap': () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Em breve: Grupo de Materiais')),
            ),
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Text(
              'Acesso Rápido',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: modulos.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 20, endIndent: 20),
            itemBuilder: (context, i) {
              final m = modulos[i];
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B00).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(m['icon'] as IconData,
                      size: 20, color: const Color(0xFFFF6B00)),
                ),
                title: Text(m['titulo'] as String,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(m['subtitulo'] as String,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
                trailing: const Icon(Icons.arrow_forward_ios,
                    size: 13, color: Colors.grey),
                onTap: m['onTap'] as VoidCallback,
              );
            },
          ),
        ],
      ),
    );
  }
}