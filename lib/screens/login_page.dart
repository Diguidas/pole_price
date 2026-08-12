// login_page.dart
import 'package:flutter/material.dart';
import 'package:pole_price/widgets/app_shell.dart';
import 'package:pole_price/widgets/auth_guard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pole_price/screens/home_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const Color primaryOrange = Color(0xFFFF6B00);
  static const Color textDark = Color(0xFF1A1A1A);
  static const Color textGray = Color(0xFF666666);

  bool _loading = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    // Escuta mudanças de sessão: quando o OAuth redirecionar de volta,
    // o Supabase atualiza a sessão e navegamos para a Home automaticamente.
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.session != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AuthGuard()),
        );
      }
    });
  }

  Future<void> _entrarComMicrosoft() async {
    setState(() {
      _loading = true;
      _erro = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.azure,

        // redirectTo aponta para o app em desenvolvimento.
        // Em produção, troca pelo domínio real.
        // redirectTo: 'http://localhost:3000',
        redirectTo: _redirectUrl,
        authScreenLaunchMode: LaunchMode.platformDefault,
        queryParams: {
          'tenant': 'a9c5de07-e6f6-4e5a-9094-56e82faf343e',
          // Garante que o Azure retorne e-mail, nome e perfil
          'scope': 'openid email profile User.Read',
        },
      );
      // A navegação acontece no listener do initState acima.
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = 'Erro ao conectar com a Microsoft. Tente novamente.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 800) {
            return SingleChildScrollView(child: _buildMobileLayout(context));
          }
          return _buildDesktopLayout(context);
        },
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Row(
      children: [
        // Lado esquerdo — logo
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [primaryOrange.withOpacity(0.04), Colors.white],
                center: Alignment.center,
                radius: 0.8,
              ),
            ),
            padding: const EdgeInsets.all(60),
            child: Center(
              child: Image.asset(
                'assets/logo.png',
                height: 380,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _buildLogoFallback(),
              ),
            ),
          ),
        ),
        Container(width: 1, color: Colors.grey.shade100),
        // Lado direito — formulário
        Expanded(
          flex: 3,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(60),
            child: Center(child: _buildLoginContent(context)),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          Image.asset(
            'assets/images/logo_branca.png',
            height: 160,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.monetization_on_outlined,
              size: 80,
              color: primaryOrange,
            ),
          ),
          const SizedBox(height: 60),
          _buildLoginContent(context),
        ],
      ),
    );
  }

  Widget _buildLoginContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Bem-vindo ao\nPole Price',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: textDark,
            height: 1.2,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Acesse a plataforma de gerenciamento de tabelas utilizando suas credenciais Microsoft corporativas.',
          style: TextStyle(fontSize: 15, color: textGray, height: 1.5),
        ),
        const SizedBox(height: 48),

        _buildMicrosoftButton(),

        // Mensagem de erro
        if (_erro != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFEF4444).withOpacity(0.3),
              ),
            ),
            child: Text(
              _erro!,
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],

        const SizedBox(height: 32),
        Center(
          child: TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(foregroundColor: textGray),
            child: const Text(
              'Precisa de ajuda com o acesso corporativo?',
              style: TextStyle(
                fontSize: 13,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMicrosoftButton() {
    return Container(
      decoration: BoxDecoration(
        color: _loading ? primaryOrange.withOpacity(0.7) : primaryOrange,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: primaryOrange.withOpacity(0.25),
            spreadRadius: 1,
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _loading ? null : _entrarComMicrosoft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_loading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else ...[
                  // Ícone da Microsoft (grade de 4 quadrados)
                  _microsoftIcon(),
                  const SizedBox(width: 12),
                ],
                const SizedBox(width: 4),
                Text(
                  _loading ? 'Conectando...' : 'Entrar com conta Microsoft',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Ícone da Microsoft feito com CustomPaint (4 quadrados coloridos)
  Widget _microsoftIcon() {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _MicrosoftIconPainter()),
    );
  }

  Widget _buildLogoFallback() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: primaryOrange.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.monetization_on_outlined,
            size: 90,
            color: primaryOrange,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'POLE PRICE',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: textDark,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 50,
          height: 4,
          decoration: BoxDecoration(
            color: primaryOrange,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

// Pinta o logo da Microsoft: 4 quadrados (vermelho, verde, amarelo, azul)
class _MicrosoftIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width * 0.08;
    final half = (size.width - gap) / 2;

    final rects = [
      // Superior esquerdo — vermelho
      Rect.fromLTWH(0, 0, half, half),
      // Superior direito — verde
      Rect.fromLTWH(half + gap, 0, half, half),
      // Inferior esquerdo — amarelo
      Rect.fromLTWH(0, half + gap, half, half),
      // Inferior direito — azul
      Rect.fromLTWH(half + gap, half + gap, half, half),
    ];

    final colors = [
      const Color(0xFFF25022),
      const Color(0xFF7FBA00),
      const Color(0xFFFFB900),
      const Color(0xFF00A4EF),
    ];

    for (var i = 0; i < 4; i++) {
      canvas.drawRect(rects[i], Paint()..color = colors[i]);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String get _redirectUrl {
  final host = Uri.base.host;
  if (host == 'localhost') {
    return 'http://localhost:3000';
  }
  return Uri.base.origin;
}
