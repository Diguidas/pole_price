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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  bool _loading = true;

  // Métricas — preenchidas de acordo com o role
  int _totalPendentes = 0;
  int _totalAprovados = 0;
  int _totalRejeitados = 0;
  int _totalDrafts = 0;
  List<Map<String, dynamic>> _ultimosPendentes = [];

  // Animação para o ponto de atividade pulsar
  late AnimationController _pulseController;

  // ── Dados do usuário ────────────────────────────────────────────────────
  String get _userEmail => _supabase.auth.currentUser?.email ?? '';
  String get _userName =>
      _supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
      _supabase.auth.currentUser?.userMetadata?['name'] as String? ??
      _userEmail.split('@').first;
  String get _userInitials {
    final parts = _userName.trim().split(' ');
    if (parts.length >= 2)
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
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
    UserRole.admin => const Color(0xFF6366F1), // Indigo
    UserRole.gestor => const Color(0xFF0EA5E9), // Sky Blue
    UserRole.aprovador => const Color(0xFF10B981), // Emerald
    UserRole.visualizador => const Color(0xFF64748B), // Slate
    _ => Colors.grey,
  };

  // ── Carregamento contextual ─────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _carregarDados();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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
        await _carregarVisualizador();
      }
    } catch (e) {
      debugPrint('HomeScreen._carregarDados: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _carregarAdmin() async {
    final res = await _supabase
        .from('price_drafts')
        .select(
          'id, status, created_at, created_by_email, price_lists!master_list_id(description)',
        )
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

  Future<void> _carregarAprovador() async {
    final res = await _supabase
        .from('price_drafts')
        .select(
          'id, status, created_at, created_by_email, price_lists!master_list_id(description)',
        )
        .order('created_at', ascending: false);

    final todos = res as List;
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

  Future<void> _carregarGestor() async {
    final res = await _supabase
        .from('price_drafts')
        .select(
          'id, status, created_at, created_by_email, price_lists!master_list_id(description)',
        )
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

  Future<void> _carregarVisualizador() async {
    final res = await _supabase.from('price_drafts').select('status');
    final todos = res as List;
    _totalPendentes = todos.where((d) => d['status'] == 'pending').length;
    _totalAprovados = todos.where((d) => d['status'] == 'approved').length;
    _totalRejeitados = todos.where((d) => d['status'] == 'rejected').length;
    _totalDrafts = todos.length;
    _ultimosPendentes = [];
  }

  List<Map<String, dynamic>> get _atalhos {
    return [
      if (_perm.podeVerPrecos)
        {
          'titulo': 'Gestão de Preços',
          'subtitulo': 'Tabelas e simulações rápidas',
          'icon': Icons.trending_up_rounded,
          'page': AppPage.precos,
        },
      if (_perm.podeVerAprovacoes)
        {
          'titulo': 'Aprovações',
          'subtitulo': 'Revisão de rascunhos pendentes',
          'icon': Icons.verified_user_rounded,
          'page': AppPage.aprovacoes,
        },
      if (_perm.podeVerGrupos)
        {
          'titulo': 'Grupos de Materiais',
          'subtitulo': 'Agrupamento estratégico de SKUs',
          'icon': Icons.widgets_rounded,
          'page': AppPage.grupos,
        },
      if (_perm.podeVerPoliticas)
        {
          'titulo': 'Políticas de Preço',
          'subtitulo': 'Regras de margem e markup',
          'icon': Icons.rule_folder_rounded,
          'page': AppPage.politicas,
        },
      if (_perm.podeVerHistorico)
        {
          'titulo': 'Histórico',
          'subtitulo': 'Log e auditoria de alterações',
          'icon': Icons.manage_search_rounded,
          'page': AppPage.historico,
        },
      if (_perm.podeVerRelatorio)
        {
          'titulo': 'Relatórios',
          'subtitulo': 'Métricas avançadas e exportações',
          'icon': Icons.analytics_rounded,
          'page': AppPage.relatorio,
        },
      if (_perm.podeVerConfig)
        {
          'titulo': 'Configurações',
          'subtitulo': 'Controle de acessos e usuários',
          'icon': Icons.tune_rounded,
          'page': AppPage.config,
        },
    ];
  }

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

  String get _subtituloMetricaPendentes => switch (_perm.permissao?.role) {
    UserRole.gestor => 'Meus envios pendentes',
    UserRole.aprovador => 'Aguardando minha ação',
    _ => 'Total pendentes',
  };

  String get _subtituloMetricaAprovados => switch (_perm.permissao?.role) {
    UserRole.gestor => 'Meus rascunhos aprovados',
    _ => 'Aprovados',
  };

  String get _subtituloFeed => switch (_perm.permissao?.role) {
    UserRole.gestor => 'Meus Envios Pendentes',
    UserRole.aprovador => 'Aguardando Sua Aprovação',
    _ => 'Fluxo de Rascunhos Pendentes',
  };

  String get _subtituloBoasVindas => switch (_perm.permissao?.role) {
    UserRole.admin => 'Visão operacional completa da plataforma.',
    UserRole.gestor =>
      'Gerencie seus rascunhos e acompanhe os status de aprovação.',
    UserRole.aprovador =>
      'Você possui $_totalPendentes solicitações sob sua responsabilidade.',
    UserRole.visualizador =>
      'Consulta rápida de preços e relatórios disponíveis.',
    _ => 'Resumo das suas operações.',
  };

  // ────────────────────────────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const corLaranja = Color(0xFFFF6B00);
    const corTextoPrincipal = Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Fundo suave e tecnológico
      body: Column(
        children: [
          // ── TOPBAR FLUTUANTE (Sem bordas duras, sombra suave e respiro moderno) ──
          Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              boxShadow: [
                BoxShadow(
                  color: const Color(0x03000000),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Indicador de Sistema Ativo
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withOpacity(0.3 + (_pulseController.value * 0.7)),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF10B981),
                              width: 1.5,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Visão Geral',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: corTextoPrincipal,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
                const Spacer(),

                // Perfil Unificado com Badge de Role Flutuante
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: corLaranja,
                        child: Text(
                          _userInitials,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: corTextoPrincipal,
                            ),
                          ),
                          Text(
                            _roleBadge,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _roleColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Botão Logout Minimalista
                IconButton(
                  icon: const Icon(
                    Icons.power_settings_new_rounded,
                    color: Color(0xFF94A3B8),
                    size: 20,
                  ),
                  tooltip: 'Sair do Sistema',
                  onPressed: _sair,
                  style: IconButton.styleFrom(
                    hoverColor: const Color(0xFFF1F5F9),
                  ),
                ),
              ],
            ),
          ),

          // ── CORPO DA PÁGINA (Layout Bento Grid Assimétrico) ──────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: corLaranja,
                      strokeWidth: 3,
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _carregarDados,
                    color: corLaranja,
                    backgroundColor: Colors.white,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── HEADER IMERSIVO (Foco na Experiência do Usuário) ──
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [corLaranja, corLaranja.withRed(240)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: corLaranja.withOpacity(0.15),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Olá, $_userName',
                                        style: const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _subtituloBoasVindas,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.85),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Ação Rápida de Refresh Integrada ao Header
                                Material(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(50),
                                  child: InkWell(
                                    onTap: _carregarDados,
                                    borderRadius: BorderRadius.circular(50),
                                    child: const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Icon(
                                        Icons.sync_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          // ── BENTO GRID DE MÉTRICAS (Assimétricas e Dinâmicas) ──
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final cardWidth = (constraints.maxWidth - 32) / 3;
                              return Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: [
                                  // Card Hero (Destaque Principal de Pendentes)
                                  _bentoMetricCardHero(
                                    label: _subtituloMetricaPendentes,
                                    valor: _totalPendentes,
                                    width:
                                        cardWidth *
                                        1.4, // Mais largo por ser a ação principal
                                    cor: corLaranja,
                                  ),
                                  // Card Secundário 1 (Aprovados)
                                  _bentoMetricCard(
                                    label: _subtituloMetricaAprovados,
                                    valor: _totalAprovados,
                                    width: cardWidth * 0.8,
                                    cor: const Color(0xFF10B981),
                                    icon: Icons.check_circle_outline_rounded,
                                  ),
                                  // Card Secundário 2 (Rejeitados e Total em Mini-Grid Vertical)
                                  SizedBox(
                                    width: cardWidth * 0.8,
                                    height: 128,
                                    child: Column(
                                      children: [
                                        _bentoMiniCard(
                                          label: 'Rejeitados',
                                          valor: _totalRejeitados,
                                          cor: const Color(0xFFEF4444),
                                        ),
                                        const SizedBox(height: 8),
                                        _bentoMiniCard(
                                          label: 'Rascunhos gerais',
                                          valor: _totalDrafts,
                                          cor: const Color(0xFF6366F1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),

                          const SizedBox(height: 36),
                          _renderBentoWorkspace(),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── SEÇÃO INTEGRADA DE FLUXOS E ATALHOS ──────────────────────────────────

  Widget _renderBentoWorkspace() {
    final atalhos = _atalhos;

    if (atalhos.isEmpty) return _bentoFeed();

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        // Estrutura 62% / 38% para uma distribuição dinâmica na tela
        final feedWidth = (totalWidth - 24) * 0.62;
        final atalhoWidth = (totalWidth - 24) * 0.38;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: feedWidth, child: _bentoFeed()),
            const SizedBox(width: 24),
            SizedBox(width: atalhoWidth, child: _bentoAcessoRapido(atalhos)),
          ],
        );
      },
    );
  }

  // ── COMPONENTES DE DESIGN (BENTO CARDS) ──────────────────────────────────

  // Card Hero de Métricas (Principal de Pendentes)
  Widget _bentoMetricCardHero({
    required String label,
    required int valor,
    required double width,
    required Color cor,
  }) {
    return Container(
      width: width < 280 ? 280 : width,
      height: 128,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0x02000000),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade500,
                    letterSpacing: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ações Recomendadas',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '$valor',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: cor,
                letterSpacing: -1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Card de Métrica Padrão Bento
  Widget _bentoMetricCard({
    required String label,
    required int valor,
    required double width,
    required Color cor,
    required IconData icon,
  }) {
    return Container(
      width: width < 180 ? 180 : width,
      height: 128,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0x02000000),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$valor',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: cor,
                  letterSpacing: -1,
                ),
              ),
              Icon(icon, color: cor.withOpacity(0.4), size: 20),
            ],
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // Card de Métrica Compacto (Mini-Grid)
  Widget _bentoMiniCard({
    required String label,
    required int valor,
    required Color cor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                '$valor',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── FEED DE PROCESSOS (Visual Timeline e Cards com Microinterações) ──

  Widget _bentoFeed() {
    const corLaranja = Color(0xFFFF6B00);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0x02000000),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _subtituloFeed,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Últimas atualizações operacionais recebidas',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (_perm.podeVerAprovacoes)
                  TextButton(
                    onPressed: () =>
                        AppShell.of(context).goTo(AppPage.aprovacoes),
                    style: TextButton.styleFrom(
                      foregroundColor: corLaranja,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: corLaranja.withOpacity(0.06),
                    ),
                    child: const Text(
                      'Ver Tudo',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          if (_ultimosPendentes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(56),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.spa_rounded,
                      size: 36,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _perm.isVisualizador
                          ? 'Sua conta não possui visualização ativa de rascunhos.'
                          : 'Sua esteira de trabalho está totalmente livre!',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ultimosPendentes.length,
              itemBuilder: (context, i) {
                final d = _ultimosPendentes[i];
                final priceList = d['price_lists'] as Map<String, dynamic>?;
                final nome =
                    priceList?['description'] ?? 'Sem descrição atribuída';
                final idCurto = (d['id'] as String).substring(0, 8);
                final criadoEm = d['created_at'] as String? ?? '';
                final dataFormatada = criadoEm.length >= 10
                    ? criadoEm.substring(0, 10).split('-').reversed.join('/')
                    : criadoEm;
                final criador = d['created_by_email'] as String? ?? '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Row(
                    children: [
                      // Status indicator block
                      Container(
                        width: 4,
                        height: 36,
                        decoration: BoxDecoration(
                          color: corLaranja,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nome,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Por: ${criador.isNotEmpty ? criador : 'ID $idCurto'}  •  $dataFormatada',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade400,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Action indicator button / badge
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: InkWell(
                          onTap: _perm.podeVerAprovacoes
                              ? () => AppShell.of(
                                  context,
                                ).goTo(AppPage.aprovacoes)
                              : null,
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'Revisar',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 14,
                                  color: Color(0xFF475569),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── SEÇÃO DE ATALHOS / ACESSO RÁPIDO (Visual Cards Modernos) ──

  Widget _bentoAcessoRapido(List<Map<String, dynamic>> modulos) {
    const corLaranja = Color(0xFFFF6B00);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0x02000000),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Text(
              'Acesso Rápido',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: modulos.length,
            itemBuilder: (context, i) {
              final m = modulos[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () =>
                        AppShell.of(context).goTo(m['page'] as AppPage),
                    borderRadius: BorderRadius.circular(16),
                    hoverColor: const Color(0xFFF8FAFC),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: corLaranja.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              m['icon'] as IconData,
                              size: 18,
                              color: corLaranja,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m['titulo'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  m['subtitulo'] as String,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade400,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_outward_rounded,
                            size: 14,
                            color: Color(0xFF94A3B8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
