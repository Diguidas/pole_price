// lib/widgets/auth_guard.dart
//
// Colocado entre o login e o AppShell.
// Carrega as permissões do usuário e:
//   - Mostra loading enquanto busca
//   - Mostra tela de "sem acesso" se não tiver role cadastrada
//   - Libera o AppShell se tudo ok

import 'package:flutter/material.dart';
import 'package:pole_price/controllers/permissao_controller.dart';
import 'package:pole_price/widgets/app_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pole_price/screens/login_page.dart';

class AuthGuard extends StatefulWidget {
  const AuthGuard({super.key});

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  static const _laranja = Color(0xFFFF6B00);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final ctrl = PermissaoController.instance;
    ctrl.addListener(_onPermissaoChanged);
    await ctrl.init();
  }

  void _onPermissaoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PermissaoController.instance.removeListener(_onPermissaoChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = PermissaoController.instance;

    // Carregando permissões
    if (ctrl.loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8F9FA),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _laranja),
              SizedBox(height: 16),
              Text(
                'Carregando permissões...',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // Sem role cadastrada
    if (ctrl.erro == 'sem_permissao') {
      return _SemAcesso(
        email: Supabase.instance.client.auth.currentUser?.email ?? '',
        onSair: _sair,
      );
    }

    // Erro genérico (problema de rede, etc)
    if (ctrl.erro != null) {
      return _ErroCarregamento(
        erro: ctrl.erro!,
        onRetry: () => PermissaoController.instance.recarregar(),
        onSair: _sair,
      );
    }

    // Tudo ok — entra no app
    return const AppShell();
  }

  Future<void> _sair() async {
    await Supabase.instance.client.auth.signOut();
    PermissaoController.reset();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tela de sem acesso
// ─────────────────────────────────────────────────────────────────────────────
class _SemAcesso extends StatelessWidget {
  final String email;
  final VoidCallback onSair;

  const _SemAcesso({required this.email, required this.onSair});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.lock_outline,
                  size: 32,
                  color: Colors.orange.shade700,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Acesso não autorizado',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'O usuário $email não possui permissão de acesso ao Pole Price.\n\nSolicite ao administrador que configure seu perfil.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onSair,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Sair da conta',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tela de erro de carregamento
// ─────────────────────────────────────────────────────────────────────────────
class _ErroCarregamento extends StatelessWidget {
  final String erro;
  final VoidCallback onRetry;
  final VoidCallback onSair;

  const _ErroCarregamento({
    required this.erro,
    required this.onRetry,
    required this.onSair,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 32,
                  color: Colors.red.shade600,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Erro ao carregar permissões',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                erro,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSair,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Sair',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B00),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Tentar novamente'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
