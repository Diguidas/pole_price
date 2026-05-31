// lib/screens/config_screen.dart
import 'package:flutter/material.dart';
import 'package:pole_price/controllers/permissao_controller.dart';
import 'package:pole_price/models/permissao_model.dart';
import 'package:pole_price/service/permissao_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  // Paleta de Cores Premium unificada do ecossistema
  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate400 = Color(0xFF94A3B8);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _slate100 = Color(0xFFF1F5F9);
  static const _bgSuave = Color(0xFFF8FAFC);

  bool _loading = true;
  List<UsuarioPermissao> _usuarios = [];
  UsuarioPermissao? _selecionado;

  // Dados auxiliares para o painel de edição
  List<Map<String, dynamic>> _todasListas = [];
  List<Map<String, dynamic>> _todosGrupos = [];
  bool _loadingAux = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final usuarios = await PermissaoController.instance.listarTodos();
      setState(() {
        _usuarios = usuarios;
        if (_selecionado != null) {
          // Atualiza o objeto selecionado com os novos dados carregados
          _selecionado = usuarios.firstWhere(
            (u) => u.email == _selecionado!.email,
            orElse: () => usuarios.first,
          );
        }
      });
    } catch (e) {
      _snack('Erro ao carregar usuários: $e', erro: true);
    } finally { // Corrigido aqui de final para finally
      setState(() => _loading = false);
    }
  }

  Future<void> _carregarAux() async {
    if (_todasListas.isNotEmpty) return;
    setState(() => _loadingAux = true);
    try {
      final supabase = Supabase.instance.client;
      final listas = await supabase
          .from('price_lists')
          .select('id, description')
          .order('description');
      final grupos = await supabase
          .from('pricing_clusters')
          .select('id, name')
          .order('name');
      setState(() {
        _todasListas = (listas as List).cast<Map<String, dynamic>>();
        _todosGrupos = (grupos as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      _snack('Erro ao carregar listas/grupos: $e', erro: true);
    } finally {
      setState(() => _loadingAux = false);
    }
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: erro ? Colors.red : const Color(0xFF047857),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  Future<void> _abrirNovoUsuario() async {
    await _carregarAux();
    if (!mounted) return;

    final novo = await showDialog<UsuarioPermissao>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogUsuario(
        todasListas: _todasListas,
        todosGrupos: _todosGrupos,
      ),
    );

    if (novo == null) return;

    try {
      await PermissaoController.instance.salvarPermissao(novo);
      _snack('Usuário adicionado com sucesso!');
      _carregar();
    } catch (e) {
      _snack('Erro ao salvar: $e', erro: true);
    }
  }

  Future<void> _editarUsuario(UsuarioPermissao usuario) async {
    await _carregarAux();
    if (!mounted) return;

    final editado = await showDialog<UsuarioPermissao>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogUsuario(
        usuario: usuario,
        todasListas: _todasListas,
        todosGrupos: _todosGrupos,
      ),
    );

    if (editado == null) return;

    try {
      await PermissaoController.instance.salvarPermissao(editado);
      _snack('Permissões atualizadas com sucesso!');
      setState(() => _selecionado = editado);
      _carregar();
    } catch (e) {
      _snack('Erro ao salvar: $e', erro: true);
    }
  }

  Future<void> _confirmarRemocao(UsuarioPermissao usuario) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remover acesso do usuário?',
          style: TextStyle(fontWeight: FontWeight.w900, color: _slate900, letterSpacing: -0.5),
        ),
        content: Text(
          'O acesso de ${usuario.email} será permanentemente revogado e bloqueado do sistema de rascunhos imediatamente.',
          style: const TextStyle(color: _slate600, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: _slate600, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bloquear e Remover', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      await PermissaoController.instance.removerUsuario(usuario.email);
      _snack('Usuário removido do sistema.');
      setState(() => _selecionado = null);
      _carregar();
    } catch (e) {
      _snack('Erro ao remover: $e', erro: true);
    }
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
                ? const Center(child: CircularProgressIndicator(color: _laranja))
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 380, child: _listaUsuarios()),
                        const SizedBox(width: 24),
                        Expanded(child: _painelDetalhe()),
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
        boxShadow: [BoxShadow(color: Color(0x02000000), blurRadius: 15, offset: Offset(0, 4))],
        border: Border(bottom: BorderSide(color: _slate100)),
      ),
      child: Row(
        children: [
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Controle de Acessos',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _slate900, letterSpacing: -0.5),
              ),
              Text(
                'Gerenciamento global de permissões, perfis comerciais e visibilidade de tabelas',
                style: TextStyle(fontSize: 12, color: _slate600, fontWeight: FontWeight.w500),
              )
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.person_add_rounded, size: 16),
            label: const Text('Novo Usuário'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _laranja,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            onPressed: _abrirNovoUsuario,
          ),
        ],
      ),
    );
  }

  // ── Lista de Usuários Lateral ─────────────────────────────────────────────
  Widget _listaUsuarios() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _slate200),
        boxShadow: const [BoxShadow(color: Color(0x01000000), blurRadius: 20, offset: Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                const Text(
                  'Membros Ativos',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _slate900),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: _bgSuave, borderRadius: BorderRadius.circular(6), border: Border.all(color: _slate200)),
                  child: Text(
                    '${_usuarios.length}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate600),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _slate100),
          Expanded(
            child: _usuarios.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline_rounded, size: 36, color: _slate400),
                        const SizedBox(height: 8),
                        const Text('Nenhum usuário localizado.', style: TextStyle(color: _slate600, fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _usuarios.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: _slate100),
                    itemBuilder: (_, i) {
                      final u = _usuarios[i];
                      final ativo = _selecionado?.email == u.email;
                      return InkWell(
                        onTap: () => setState(() => _selecionado = u),
                        hoverColor: _laranja.withOpacity(0.01),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          color: ativo ? _laranja.withOpacity(0.04) : null,
                          child: Row(
                            children: [
                              _avatar(u.email, ativo: ativo),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      u.email,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: ativo ? FontWeight.w800 : FontWeight.w600,
                                        color: ativo ? _laranja : _slate900,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    _roleBadge(u.role),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: ativo ? _laranja : _slate400,
                              ),
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

  // ── Painel de Detalhes à Direita ──────────────────────────────────────────
  Widget _painelDetalhe() {
    if (_selecionado == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _slate200),
          boxShadow: const [BoxShadow(color: Color(0x01000000), blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(color: _bgSuave, shape: BoxShape.circle),
                child: const Icon(Icons.shield_outlined, size: 44, color: _slate400),
              ),
              const SizedBox(height: 16),
              const Text(
                'Painel de Auditoria Individual',
                style: TextStyle(fontWeight: FontWeight.w700, color: _slate900, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                'Selecione um membro da lista para analisar ou editar escopos',
                style: TextStyle(color: _slate600, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final u = _selecionado!;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _slate200),
        boxShadow: const [BoxShadow(color: Color(0x01000000), blurRadius: 20, offset: Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card do usuário
          Container(
            padding: const EdgeInsets.all(24),
            color: _bgSuave,
            child: Row(
              children: [
                _avatar(u.email, size: 48, ativo: true),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u.email,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _slate900, letterSpacing: -0.3),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _roleBadge(u.role),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.mode_edit_outline_rounded, size: 18),
                  tooltip: 'Alterar Escopo',
                  onPressed: () => _editarUsuario(u),
                  color: _slate600,
                  // CORRIGIDO: de borderSide direto para side: BorderSide(...)
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white, 
                    side: const BorderSide(color: _slate200), 
                    padding: const EdgeInsets.all(10),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                  tooltip: 'Revogar Acesso',
                  onPressed: () => _confirmarRemocao(u),
                  color: const Color(0xFFB91C1C),
                  // CORRIGIDO: de borderSide direto para side: BorderSide(...)
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFFFF1F2), 
                    side: const BorderSide(color: Color(0xFFFFE4E6)), 
                    padding: const EdgeInsets.all(10),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _slate200),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _secao('Módulos e Telas Habilitadas', Icons.dashboard_customize_outlined),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _telasAcessiveis(u)
                        .map((t) => _chip(t, const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)))
                        .toList(),
                  ),
                  
                  if (u.isGestor || u.isAdmin) ...[
                    const SizedBox(height: 28),
                    _secao('Listas de Preço com Permissão de Escrita', Icons.table_chart_outlined),
                    const SizedBox(height: 10),
                    u.isAdmin
                        ? _infoText('Administradores possuem permissão de escrita global irrestrita.')
                        : u.listIds.isEmpty
                            ? _infoText('Escrita liberada para todas as tabelas comerciais.')
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: u.listIds
                                    .map((id) => _chip(id, _laranja.withOpacity(0.08), _laranja))
                                    .toList(),
                              ),

                    const SizedBox(height: 28),
                    _secao('Grupos de Materiais (Clusters) Autorizados', Icons.account_tree_outlined),
                    const SizedBox(height: 10),
                    u.isAdmin
                        ? _infoText('Administradores possuem visão e edição de todos os clusters de produtos.')
                        : u.clusterIds.isEmpty
                            ? _infoText('Acesso livre a todos os grupos organizacionais de materiais.')
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: u.clusterIds
                                    .map((id) => _chip(id, const Color(0xFFECFDF5), const Color(0xFF047857)))
                                    .toList(),
                              ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _telasAcessiveis(UsuarioPermissao u) {
    final telas = <String>[];
    if (u.podeVerPrecos) telas.add('Módulo Preços');
    if (u.podeVerAprovacoes) telas.add('Módulo Aprovações');
    if (u.podeVerGrupos) telas.add('Clusters/Grupos');
    if (u.podeVerPoliticas) telas.add('Políticas de Reajuste');
    if (u.podeVerHistorico) telas.add('Histórico Comercial');
    if (u.podeVerRelatorio) telas.add('Relatórios de Custo');
    if (u.podeVerConfig) telas.add('Configurações do Sistema');
    return telas;
  }

  // ── Helpers Visuais Premium ───────────────────────────────────────────────
  Widget _avatar(String email, {double size = 34, bool ativo = false}) {
    final inicial = email.isNotEmpty ? email[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ativo ? _laranja.withOpacity(0.08) : _slate100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ativo ? _laranja.withOpacity(0.2) : _slate200),
      ),
      child: Center(
        child: Text(
          inicial,
          style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w900, color: ativo ? _laranja : _slate600),
        ),
      ),
    );
  }

  Widget _roleBadge(UserRole role) {
    final (bg, fg) = switch (role) {
      UserRole.admin => (const Color(0xFFF3E8FF), const Color(0xFF7E22CE)),
      UserRole.gestor => (_laranja.withOpacity(0.08), _laranja),
      UserRole.aprovador => (const Color(0xFFECFDF5), const Color(0xFF047857)),
      UserRole.visualizador => (const Color(0xFFF1F5F9), const Color(0xFF475569)),
    };
    return IntrinsicWidth(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Center(
          child: Text(
            role.label.toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.3),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: fg.withOpacity(0.15))),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _secao(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _slate600),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _slate900),
        ),
      ],
    );
  }

  Widget _infoText(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _bgSuave, borderRadius: BorderRadius.circular(10), border: Border.all(color: _slate100)),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: _slate600, fontWeight: FontWeight.w500, height: 1.4),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Dialog Customizado de Criação / Edição de Usuários (Layout Elegante)
// ═════════════════════════════════════════════════════════════════════════════
class _DialogUsuario extends StatefulWidget {
  final UsuarioPermissao? usuario;
  final List<Map<String, dynamic>> todasListas;
  final List<Map<String, dynamic>> todosGrupos;

  const _DialogUsuario({
    this.usuario,
    required this.todasListas,
    required this.todosGrupos,
  });

  @override
  State<_DialogUsuario> createState() => _DialogUsuarioState();
}

class _DialogUsuarioState extends State<_DialogUsuario> {
  static const _laranja = Color(0xFFFF6B00);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate600 = Color(0xFF475569);
  static const _slate400 = Color(0xFF94A3B8);
  static const _slate200 = Color(0xFFE2E8F0);
  static const _slate100 = Color(0xFFF1F5F9);
  static const _bgSuave = Color(0xFFF8FAFC);

  late final TextEditingController _emailCtrl;
  late UserRole _role;
  late Set<String> _listsSelecionadas;
  late Set<String> _groupsSelecionados;

  bool get isEdicao => widget.usuario != null;

  @override
  void initState() {
    super.initState();
    final u = widget.usuario;
    _emailCtrl = TextEditingController(text: u?.email ?? '');
    _role = u?.role ?? UserRole.gestor;
    _listsSelecionadas = Set.from(u?.listIds ?? []);
    _groupsSelecionados = Set.from(u?.clusterIds ?? []);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.white,
      child: SizedBox(
        width: 600,
        height: 700,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header do Dialog
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              color: _bgSuave,
              child: Row(
                children: [
                  Icon(isEdicao ? Icons.admin_panel_settings_outlined : Icons.person_add_alt_1_outlined, color: _laranja, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    isEdicao ? 'Alterar Escopo de Acesso' : 'Cadastrar Novo Operador',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _slate900, letterSpacing: -0.4),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: _slate600),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(hoverColor: _slate200),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _slate200),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Campo Email
                    const Text('Endereço de Email Corporal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _slate900)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailCtrl,
                      enabled: !isEdicao,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'exemplo@empresa.com.br',
                        hintStyle: const TextStyle(color: _slate400, fontWeight: FontWeight.w400),
                        isDense: true,
                        filled: true,
                        fillColor: isEdicao ? _slate100 : Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _slate200)),
                        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _slate200)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _laranja, width: 1.5)),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Seleção de Roles
                    const Text('Perfil de Acesso Corporativo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _slate900)),
                    const SizedBox(height: 8),
                    Row(
                      children: UserRole.values
                          .map((r) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: _cardRole(r),
                                ),
                              ))
                          .toList(),
                    ),

                    // Configurações Específicas de Escopo (Apenas Gestores)
                    if (_role == UserRole.gestor) ...[
                      const SizedBox(height: 24),
                      const Divider(color: _slate100),
                      const SizedBox(height: 12),
                      
                      // Bloco das Listas
                      _subHeaderEscopo(
                        titulo: 'Tabelas de Preço Vinculadas',
                        descricao: 'Se nenhuma for selecionada, o gestor terá escrita irrestrita em todas.',
                        todosMarcados: _listsSelecionadas.length == widget.todasListas.length,
                        onToggleTodos: () => setState(() {
                          if (_listsSelecionadas.length == widget.todasListas.length) {
                            _listsSelecionadas.clear();
                          } else {
                            _listsSelecionadas.addAll(widget.todasListas.map((l) => l['id'].toString()));
                          }
                        }),
                      ),
                      const SizedBox(height: 8),
                      // CORRIGIDO: de maxHeight direto para constraints: BoxConstraints(maxHeight: 140)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 140),
                        decoration: BoxDecoration(color: _bgSuave, borderRadius: BorderRadius.circular(12), border: Border.all(color: _slate200)),
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          children: widget.todasListas.map((l) {
                            final id = l['id'].toString();
                            final nome = l['description']?.toString() ?? id;
                            final marq = _listsSelecionadas.contains(id);
                            return CheckboxListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              value: marq,
                              title: Text(nome, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _slate900)),
                              subtitle: Text(id, style: const TextStyle(fontSize: 10, color: _slate600)),
                              activeColor: _laranja,
                              checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              onChanged: (v) => setState(() => v == true ? _listsSelecionadas.add(id) : _listsSelecionadas.remove(id)),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 24),
                      
                      // Bloco dos Clusters
                      _subHeaderEscopo(
                        titulo: 'Famílias/Clusters de Materiais Autorizados',
                        descricao: 'Restrinja os grupos de produtos que este gestor pode atualizar.',
                        todosMarcados: _groupsSelecionados.length == widget.todosGrupos.length,
                        onToggleTodos: () => setState(() {
                          if (_groupsSelecionados.length == widget.todosGrupos.length) {
                            _groupsSelecionados.clear();
                          } else {
                            _groupsSelecionados.addAll(widget.todosGrupos.map((g) => g['id'].toString()));
                          }
                        }),
                      ),
                      const SizedBox(height: 8),
                      // CORRIGIDO: de maxHeight direto para constraints: BoxConstraints(maxHeight: 140)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 140),
                        decoration: BoxDecoration(color: _bgSuave, borderRadius: BorderRadius.circular(12), border: Border.all(color: _slate200)),
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          children: widget.todosGrupos.map((g) {
                            final id = g['id'].toString();
                            final nome = g['name']?.toString() ?? id;
                            final marq = _groupsSelecionados.contains(id);
                            return CheckboxListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              value: marq,
                              title: Text(nome, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _slate900)),
                              activeColor: _laranja,
                              checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              onChanged: (v) => setState(() => v == true ? _groupsSelecionados.add(id) : _groupsSelecionados.remove(id)),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: _slate200),
            // Rodapé com Ações
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: _slate200),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancelar', style: TextStyle(color: _slate600, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _laranja,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _salvar,
                      child: Text(isEdicao ? 'Salvar Alterações' : 'Confirmar Cadastro', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subHeaderEscopo({required String titulo, required String descricao, required bool todosMarcados, required VoidCallback onToggleTodos}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _slate900))),
            TextButton(
              onPressed: onToggleTodos,
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text(todosMarcados ? 'Desmarcar todos' : 'Marcar todos', style: const TextStyle(fontSize: 11, color: _laranja, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(descricao, style: const TextStyle(fontSize: 11, color: _slate600, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _cardRole(UserRole role) {
    final selecionado = _role == role;
    final (bg, border, fg) = selecionado
        ? switch (role) {
            UserRole.admin => (const Color(0xFFF3E8FF), const Color(0xFFC084FC), const Color(0xFF7E22CE)),
            UserRole.gestor => (_laranja.withOpacity(0.08), _laranja.withOpacity(0.4), _laranja),
            UserRole.aprovador => (const Color(0xFFECFDF5), const Color(0xFF34D399), const Color(0xFF047857)),
            UserRole.visualizador => (const Color(0xFFF1F5F9), _slate400, _slate600),
          }
        : (Colors.white, _slate200, _slate600);

    return GestureDetector(
      onTap: () => setState(() => _role = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: selecionado ? 1.5 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              role.label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: selecionado ? FontWeight.w800 : FontWeight.w600, color: fg),
            ),
          ],
        ),
      ),
    );
  }

  void _salvar() {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Informe um endereço de email válido.'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    Navigator.pop(
      context,
      UsuarioPermissao(
        email: email,
        role: _role,
        listIds: _role == UserRole.gestor ? _listsSelecionadas.toList() : [],
        clusterIds: _role == UserRole.gestor ? _groupsSelecionados.toList() : [],
      ),
    );
  }
}