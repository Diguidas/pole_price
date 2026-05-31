// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:pole_price/controllers/permissao_controller.dart';
import 'package:pole_price/models/permissao_model.dart';
import 'package:pole_price/screens/login_page.dart';
import 'package:pole_price/widgets/app_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;

  // Métricas — preenchidas de acordo com o role
  int _totalPendentes = 0;
  int _totalAprovados = 0;
  int _totalRejeitados = 0;
  int _totalDrafts = 0;
  List<Map<String, dynamic>> _ultimosPendentes = [];

  // ── Dados do usuário ────────────────────────────────────────────────────
  String get _userEmail => _supabase.auth.currentUser?.email ?? '';
  String get _userName =>
      _supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
      _supabase.auth.currentUser?.userMetadata?['name'] as String? ??
      _userEmail.split('@').first;
  String get _userInitials {
    final parts = _userName.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return _userName.isNotEmpty ? _userName[0].toUpperCase() : '?';
  }

  PermissaoController get _perm => PermissaoController.instance;

  String get _roleBadge => switch (_perm.permissao?.role) {
        UserRole.admin => 'Administrador',
        UserRole.gestor => 'Gestor',
        UserRole.aprovador => 'Aprovador',
        UserRole.visualizador => 'Visualizador',
        _ => '',
      };

  Color get _roleColor => switch (_perm.permissao?.role) {
        UserRole.admin => const Color(0xFF6366F1),
        UserRole.gestor => const Color(0xFF0EA5E9),
        UserRole.aprovador => const Color(0xFF22C55E),
        UserRole.visualizador => const Color(0xFF94A3B8),
        _ => Colors.grey,
      };

  // ── Carregamento contextual ─────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _loading = true);
    try {
      if (_perm.isAdmin) {
        await _carregarAdmin();
      } else if (_perm.isAprovador) {
        await _carregarAprovador();
      } else if (_perm.isGestor) {
        await _carregarGestor();
      } else {
        // Visualizador — só totais gerais sem dados sensíveis
        await _carregarVisualizador();
      }
    } catch (e) {
      debugPrint('HomeScreen._carregarDados: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Admin: vê tudo
  Future<void> _carregarAdmin() async {
    final res = await _supabase
        .from('price_drafts')
        .select('id, status, created_at, created_by_email, price_lists!master_list_id(description)')
        .order('created_at', ascending: false);

    final todos = res as List;
    _totalPendentes = todos.where((d) => d['status'] == 'pending').length;
    _totalAprovados = todos.where((d) => d['status'] == 'approved').length;
    _totalRejeitados = todos.where((d) => d['status'] == 'rejected').length;
    _totalDrafts = todos.length;
    _ultimosPendentes = todos
        .where((d) => d['status'] == 'pending')
        .take(5)
        .cast<Map<String, dynamic>>()
        .toList();
  }

  /// Aprovador: foca nos pendentes que ele pode aprovar
  Future<void> _carregarAprovador() async {
    final res = await _supabase
        .from('price_drafts')
        .select('id, status, created_at, created_by_email, price_lists!master_list_id(description)')
        .order('created_at', ascending: false);

    final todos = res as List;

    // Filtra por listas permitidas se não for admin
    final permitidas = _perm.listasPermitidas;
    final filtrados = permitidas.isEmpty
        ? todos
        : todos.where((d) {
            final pl = d['price_lists'] as Map?;
            return pl != null && permitidas.contains(pl['id']?.toString());
          }).toList();

    _totalPendentes = filtrados.where((d) => d['status'] == 'pending').length;
    _totalAprovados = filtrados.where((d) => d['status'] == 'approved').length;
    _totalRejeitados = filtrados.where((d) => d['status'] == 'rejected').length;
    _totalDrafts = filtrados.length;
    _ultimosPendentes = filtrados
        .where((d) => d['status'] == 'pending')
        .take(5)
        .cast<Map<String, dynamic>>()
        .toList();
  }

  /// Gestor: só seus próprios drafts
  Future<void> _carregarGestor() async {
    final res = await _supabase
        .from('price_drafts')
        .select('id, status, created_at, created_by_email, price_lists!master_list_id(description)')
        .eq('created_by_email', _userEmail)
        .order('created_at', ascending: false);

    final todos = res as List;
    _totalPendentes = todos.where((d) => d['status'] == 'pending').length;
    _totalAprovados = todos.where((d) => d['status'] == 'approved').length;
    _totalRejeitados = todos.where((d) => d['status'] == 'rejected').length;
    _totalDrafts = todos.length;
    _ultimosPendentes = todos
        .where((d) => d['status'] == 'pending')
        .take(5)
        .cast<Map<String, dynamic>>()
        .toList();
  }

  /// Visualizador: só contagens, sem lista de drafts
  Future<void> _carregarVisualizador() async {
    final res = await _supabase
        .from('price_drafts')
        .select('status');

    final todos = res as List;
    _totalPendentes = todos.where((d) => d['status'] == 'pending').length;
    _totalAprovados = todos.where((d) => d['status'] == 'approved').length;
    _totalRejeitados = todos.where((d) => d['status'] == 'rejected').length;
    _totalDrafts = todos.length;
    _ultimosPendentes = [];
  }

  // ── Atalhos filtrados por permissão ─────────────────────────────────────

  List<Map<String, dynamic>> get _atalhos {
    final todos = [
      if (_perm.podeVerPrecos)
        {
          'titulo': 'Gestão de Preços',
          'subtitulo': 'Editar tabelas e enviar para aprovação',
          'icon': Icons.attach_money_rounded,
          'page': AppPage.precos,
        },
      if (_perm.podeVerAprovacoes)
        {
          'titulo': 'Aprovações',
          'subtitulo': 'Revisar e aprovar rascunhos pendentes',
          'icon': Icons.check_circle_outline_rounded,
          'page': AppPage.aprovacoes,
        },
      if (_perm.podeVerGrupos)
        {
          'titulo': 'Grupos de Materiais',
          'subtitulo': 'Gerenciar agrupamentos de produtos',
          'icon': Icons.account_tree_outlined,
          'page': AppPage.grupos,
        },
      if (_perm.podeVerPoliticas)
        {
          'titulo': 'Políticas de Preço',
          'subtitulo': 'Cadastrar e gerenciar políticas',
          'icon': Icons.policy_outlined,
          'page': AppPage.politicas,
        },
      if (_perm.podeVerHistorico)
        {
          'titulo': 'Histórico',
          'subtitulo': 'Ver log de aprovações e criações',
          'icon': Icons.history_rounded,
          'page': AppPage.historico,
        },
      if (_perm.podeVerRelatorio)
        {
          'titulo': 'Relatórios',
          'subtitulo': 'Visualizar relatórios e exportações',
          'icon': Icons.bar_chart_rounded,
          'page': AppPage.relatorio,
        },
      if (_perm.podeVerConfig)
        {
          'titulo': 'Configurações',
          'subtitulo': 'Gerenciar usuários e permissões',
          'icon': Icons.settings_outlined,
          'page': AppPage.config,
        },
    ];
    return todos;
  }

  // ── Logout ───────────────────────────────────────────────────────────────

  Future<void> _sair() async {
    await _supabase.auth.signOut();
    PermissaoController.reset();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  // ── Labels contextuais ───────────────────────────────────────────────────

  String get _subtituloMetricaPendentes => switch (_perm.permissao?.role) {
        UserRole.gestor => 'Meus pendentes',
        UserRole.aprovador => 'Aguardando aprovação',
        _ => 'Pendentes',
      };

  String get _subtituloMetricaAprovados => switch (_perm.permissao?.role) {
        UserRole.gestor => 'Meus aprovados',
        _ => 'Aprovados',
      };

  String get _subtituloFeed => switch (_perm.permissao?.role) {
        UserRole.gestor => 'Meus Rascunhos Pendentes',
        UserRole.aprovador => 'Aguardando Sua Aprovação',
        _ => 'Rascunhos Pendentes',
      };

  // ────────────────────────────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const laranja = Color(0xFFFF6B00);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Column(
        children: [
          // ── Topbar ────────────────────────────────────────────────────
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
                  'Dashboard',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                // Badge de role
                if (_roleBadge.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _roleColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _roleBadge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _roleColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                // Avatar + nome
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: laranja.withOpacity(0.15),
                        child: Text(
                          _userInitials,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: laranja,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          if (_userEmail.isNotEmpty)
                            Text(
                              _userEmail,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.logout_outlined, color: Colors.grey),
                  tooltip: 'Sair',
                  onPressed: _sair,
                ),
              ],
            ),
          ),

          // ── Corpo ──────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF6B00)),
                  )
                : RefreshIndicator(
                    onRefresh: _carregarDados,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Olá, $_userName 👋',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _subtituloBoasVindas,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                          const SizedBox(height: 24),

                          // ── Cards de métricas ──────────────────────────
                          Row(
                            children: [
                              _metricCard(
                                label: _subtituloMetricaPendentes,
                                valor: _totalPendentes,
                                icon: Icons.hourglass_top_rounded,
                                cor: laranja,
                              ),
                              const SizedBox(width: 16),
                              _metricCard(
                                label: _subtituloMetricaAprovados,
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
                                valor: _totalDrafts,
                                icon: Icons.description_outlined,
                                cor: const Color(0xFF6366F1),
                              ),
                            ],
                          ),

                          const SizedBox(height: 28),
                          _feedEAtalhos(),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String get _subtituloBoasVindas => switch (_perm.permissao?.role) {
        UserRole.admin => 'Visão geral de toda a plataforma.',
        UserRole.gestor => 'Acompanhe seus rascunhos e tabelas.',
        UserRole.aprovador => 'Você tem $_totalPendentes rascunho(s) aguardando aprovação.',
        UserRole.visualizador => 'Consulte preços e históricos disponíveis.',
        _ => 'Aqui está o resumo de hoje.',
      };

  // ── Widgets ──────────────────────────────────────────────────────────────

  Widget _feedEAtalhos() {
    final atalhos = _atalhos;

    // Se não tem nenhum atalho disponível, mostra só o feed
    if (atalhos.isEmpty) return _feedPendentes();

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final feedWidth = (totalWidth - 16) * 3 / 5;
        final atalhoWidth = (totalWidth - 16) * 2 / 5;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: feedWidth, child: _feedPendentes()),
            const SizedBox(width: 16),
            SizedBox(width: atalhoWidth, child: _acessoRapido(atalhos)),
          ],
        );
      },
    );
  }

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
                    color: cor,
                  ),
                ),
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _feedPendentes() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Text(
                  _subtituloFeed,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_perm.podeVerAprovacoes)
                  TextButton.icon(
                    icon: const Icon(Icons.arrow_forward, size: 15),
                    label: const Text('Ver todos'),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF6B00)),
                    onPressed: () => AppShell.of(context).goTo(AppPage.aprovacoes),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_ultimosPendentes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  _perm.isVisualizador
                      ? 'Sem acesso aos detalhes de rascunhos.'
                      : 'Nenhum rascunho pendente no momento.',
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
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
                final priceList = d['price_lists'] as Map<String, dynamic>?;
                final nome = priceList?['description'] ?? 'Tabela desconhecida';
                final idCurto = (d['id'] as String).substring(0, 8);
                final criadoEm = d['created_at'] as String? ?? '';
                final dataFormatada = criadoEm.length >= 10
                    ? criadoEm.substring(0, 10).split('-').reversed.join('/')
                    : criadoEm;
                final criador = d['created_by_email'] as String? ?? '';

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
                    child: const Icon(
                      Icons.description_outlined,
                      size: 18,
                      color: Color(0xFFFF6B00),
                    ),
                  ),
                  title: Text(
                    nome,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    '${criador.isNotEmpty ? criador : 'ID: $idCurto...'}  •  $dataFormatada',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B00).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Pendente',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFF6B00),
                      ),
                    ),
                  ),
                  onTap: _perm.podeVerAprovacoes
                      ? () => AppShell.of(context).goTo(AppPage.aprovacoes)
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _acessoRapido(List<Map<String, dynamic>> modulos) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade100),
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
                  child: Icon(
                    m['icon'] as IconData,
                    size: 20,
                    color: const Color(0xFFFF6B00),
                  ),
                ),
                title: Text(
                  m['titulo'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: Text(
                  m['subtitulo'] as String,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 13, color: Colors.grey),
                onTap: () => AppShell.of(context).goTo(m['page'] as AppPage),
              );
            },
          ),
        ],
      ),
    );
  }
}