// lib/screens/config_screen.dart
//
// Tela de configurações — visível apenas para admin.
// Permite gerenciar usuários: definir role e permissões de listas/grupos.

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
  static const _laranja = Color(0xFFFF6B00);

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
      final usuarios =
          await PermissaoController.instance.listarTodos();
      setState(() => _usuarios = usuarios);
    } catch (e) {
      _snack('Erro ao carregar usuários: $e', erro: true);
    } finally {
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
      content: Text(msg),
      backgroundColor: erro ? Colors.red : Colors.green,
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
      _snack('Permissões atualizadas!');
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Remover usuário'),
        content: Text(
            'Remover ${usuario.email} do sistema? O acesso será bloqueado imediatamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      await PermissaoController.instance.removerUsuario(usuario.email);
      _snack('Usuário removido.');
      setState(() => _selecionado = null);
      _carregar();
    } catch (e) {
      _snack('Erro ao remover: $e', erro: true);
    }
  }

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
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 360, child: _listaUsuarios()),
                        const SizedBox(width: 20),
                        Expanded(child: _painelDetalhe()),
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
          const Text('Configurações',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: const Text('Novo usuário'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _laranja,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _abrirNovoUsuario,
          ),
        ],
      ),
    );
  }

  // ── Lista de usuários ─────────────────────────────────────────────────────

  Widget _listaUsuarios() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Text('Usuários',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                Text('${_usuarios.length}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _usuarios.isEmpty
                ? Center(
                    child: Text('Nenhum usuário cadastrado.',
                        style: TextStyle(color: Colors.grey.shade500)),
                  )
                : ListView.separated(
                    itemCount: _usuarios.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16),
                    itemBuilder: (_, i) {
                      final u = _usuarios[i];
                      final ativo = _selecionado?.email == u.email;
                      return InkWell(
                        onTap: () => setState(() => _selecionado = u),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          color: ativo
                              ? _laranja.withOpacity(0.06)
                              : null,
                          child: Row(
                            children: [
                              _avatar(u.email),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      u.email,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: ativo
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: ativo
                                            ? _laranja
                                            : Colors.grey.shade800,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    _roleBadge(u.role),
                                  ],
                                ),
                              ),
                              if (ativo)
                                Icon(Icons.chevron_right,
                                    size: 18, color: _laranja),
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

  // ── Painel de detalhe ─────────────────────────────────────────────────────

  Widget _painelDetalhe() {
    if (_selecionado == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline,
                  size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('Selecione um usuário para ver os detalhes',
                  style: TextStyle(color: Colors.grey.shade500)),
            ],
          ),
        ),
      );
    }

    final u = _selecionado!;

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
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(
              children: [
                _avatar(u.email, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.email,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      _roleBadge(u.role),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Editar permissões',
                  onPressed: () => _editarUsuario(u),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: Colors.red.shade400),
                  tooltip: 'Remover usuário',
                  onPressed: () => _confirmarRemocao(u),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Telas acessíveis
                  _secao('Telas acessíveis', Icons.dashboard_outlined),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _telasAcessiveis(u)
                        .map((t) => _chip(t, Colors.blue.shade50,
                            Colors.blue.shade700))
                        .toList(),
                  ),

                  const SizedBox(height: 24),

                  if (u.isGestor || u.isAdmin) ...[
                    // Listas permitidas
                    _secao('Listas de preço',
                        Icons.table_chart_outlined),
                    const SizedBox(height: 8),
                    u.isAdmin
                        ? _infoText('Admin tem acesso a todas as listas.')
                        : u.listIds.isEmpty
                            ? _infoText('Acesso a todas as listas.')
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: u.listIds
                                    .map((id) => _chip(id,
                                        _laranja.withOpacity(0.08), _laranja))
                                    .toList(),
                              ),

                    const SizedBox(height: 24),

                    // Grupos permitidos
                    _secao('Grupos de materiais',
                        Icons.account_tree_outlined),
                    const SizedBox(height: 8),
                    u.isAdmin
                        ? _infoText('Admin tem acesso a todos os grupos.')
                        : u.clusterIds.isEmpty
                            ? _infoText('Acesso a todos os grupos.')
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: u.clusterIds
                                    .map((id) => _chip(id,
                                        Colors.green.shade50,
                                        Colors.green.shade700))
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
    if (u.podeVerPrecos) telas.add('Preços');
    if (u.podeVerAprovacoes) telas.add('Aprovações');
    if (u.podeVerGrupos) telas.add('Grupos');
    if (u.podeVerPoliticas) telas.add('Políticas');
    if (u.podeVerHistorico) telas.add('Histórico');
    if (u.podeVerRelatorio) telas.add('Relatório');
    if (u.podeVerConfig) telas.add('Configurações');
    return telas;
  }

  // ── Helpers visuais ───────────────────────────────────────────────────────

  Widget _avatar(String email, {double size = 32}) {
    final inicial = email.isNotEmpty ? email[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _laranja.withOpacity(0.12),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Center(
        child: Text(inicial,
            style: TextStyle(
                fontSize: size * 0.4,
                fontWeight: FontWeight.bold,
                color: _laranja)),
      ),
    );
  }

  Widget _roleBadge(UserRole role) {
    final (bg, fg) = switch (role) {
      UserRole.admin => (Colors.purple.shade50, Colors.purple.shade700),
      UserRole.gestor => (_laranja.withOpacity(0.10), _laranja),
      UserRole.aprovador => (Colors.green.shade50, Colors.green.shade700),
      UserRole.visualizador => (Colors.red.shade50, Colors.red.shade700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(role.label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
    );
  }

  Widget _secao(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _infoText(String text) {
    return Text(text,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade500));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Dialog de criação / edição de usuário
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 560,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Text(
                    isEdicao ? 'Editar permissões' : 'Novo usuário',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Email
                    const Text('Email',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailCtrl,
                      enabled: !isEdicao,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'usuario@empresa.com',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Role
                    const Text('Perfil de acesso',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: UserRole.values
                          .map((r) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _cardRole(r),
                                ),
                              ))
                          .toList(),
                    ),

                    // Listas (só para gestor)
                    if (_role == UserRole.gestor) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Text('Listas de preço permitidas',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() =>
                                _listsSelecionadas.length ==
                                        widget.todasListas.length
                                    ? _listsSelecionadas.clear()
                                    : _listsSelecionadas.addAll(widget
                                        .todasListas
                                        .map((l) => l['id'].toString()))),
                            child: Text(
                              _listsSelecionadas.length ==
                                      widget.todasListas.length
                                  ? 'Desmarcar todas'
                                  : 'Marcar todas',
                              style: const TextStyle(
                                  fontSize: 12, color: _laranja),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Deixe em branco para permitir acesso a todas.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 8),
                      ...widget.todasListas.map((l) {
                        final id = l['id'].toString();
                        final nome = l['description']?.toString() ?? id;
                        return CheckboxListTile(
                          dense: true,
                          value: _listsSelecionadas.contains(id),
                          title: Text(nome,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(id,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500)),
                          activeColor: _laranja,
                          onChanged: (v) => setState(() => v == true
                              ? _listsSelecionadas.add(id)
                              : _listsSelecionadas.remove(id)),
                        );
                      }),

                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Text('Grupos de materiais permitidos',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() =>
                                _groupsSelecionados.length ==
                                        widget.todosGrupos.length
                                    ? _groupsSelecionados.clear()
                                    : _groupsSelecionados.addAll(widget
                                        .todosGrupos
                                        .map((g) => g['id'].toString()))),
                            child: Text(
                              _groupsSelecionados.length ==
                                      widget.todosGrupos.length
                                  ? 'Desmarcar todos'
                                  : 'Marcar todos',
                              style: const TextStyle(
                                  fontSize: 12, color: _laranja),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Deixe em branco para permitir acesso a todos.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 8),
                      ...widget.todosGrupos.map((g) {
                        final id = g['id'].toString();
                        final nome = g['name']?.toString() ?? id;
                        return CheckboxListTile(
                          dense: true,
                          value: _groupsSelecionados.contains(id),
                          title: Text(nome,
                              style: const TextStyle(fontSize: 13)),
                          activeColor: _laranja,
                          onChanged: (v) => setState(() => v == true
                              ? _groupsSelecionados.add(id)
                              : _groupsSelecionados.remove(id)),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Cancelar',
                          style: TextStyle(color: Colors.black54)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _laranja,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _salvar,
                      child: Text(isEdicao ? 'Salvar' : 'Adicionar'),
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

  Widget _cardRole(UserRole role) {
    final selecionado = _role == role;
    final (bg, border, fg) = selecionado
        ? switch (role) {
            UserRole.admin => (
                Colors.purple.shade50,
                Colors.purple.shade300,
                Colors.purple.shade700
              ),
            UserRole.gestor => (
                _laranja.withOpacity(0.08),
                _laranja.withOpacity(0.5),
                _laranja
              ),
            UserRole.aprovador => (
                Colors.green.shade50,
                Colors.green.shade300,
                Colors.green.shade700
              ),
              UserRole.visualizador => (
                Colors.red.shade50,
                Colors.red.shade300,
                Colors.red.shade700
              ),
          }
        : (Colors.white, Colors.grey.shade300, Colors.grey.shade600);

    return GestureDetector(
      onTap: () => setState(() => _role = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border, width: selecionado ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Text(role.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg)),
          ],
        ),
      ),
    );
  }

  void _salvar() {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Informe um email válido.'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    Navigator.pop(
      context,
      UsuarioPermissao(
        email: email,
        role: _role,
        listIds: _role == UserRole.gestor
            ? _listsSelecionadas.toList()
            : [],
        clusterIds: _role == UserRole.gestor
            ? _groupsSelecionados.toList()
            : [],
      ),
    );
  }
}