// login_page.dart
import 'package:flutter/material.dart';
import 'package:pole_price/screens/home_screen.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  // Definição das cores padrão do Pole Price para manter a consistência premium
  static const Color primaryOrange = Color(0xFFFF6B00); 
  static const Color textDark = Color(0xFF1A1A1A); 
  static const Color textGray = Color(0xFF666666); 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Se for uma tela de dispositivo móvel ou muito estreita, adapta o layout
          if (constraints.maxWidth < 800) {
            return SingleChildScrollView(
              child: _buildMobileLayout(context),
            );
          } else {
            return _buildDesktopLayout(context);
          }
        },
      ),
    );
  }

  // ── LAYOUT DESKTOP / WEB (O DE TIRAR O FÔLEGO) ──────────────────────────
  Widget _buildDesktopLayout(BuildContext context) {
    return Row(
      children: [
        // Lado Esquerdo: Área Visual do Logo com fundo branco e profundidade radial
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              // Um degradê radial extremamente sutil para dar acabamento de estúdio ao fundo branco
              gradient: RadialGradient(
                colors: [
                  primaryOrange.withOpacity(0.04),
                  Colors.white,
                ],
                center: Alignment.center,
                radius: 0.8,
              ),
            ),
            padding: const EdgeInsets.all(60.0),
            child: Center(
              child: Image.asset(
                'assets/logo.png', // Caminho do seu asset de logo
                height: 380,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // Fallback dinâmico se o asset não for achado
                  return _buildLogoFallback();
                },
              ),
            ),
          ),
        ),

        // Linha divisória vertical quase invisível para organizar o ambiente de forma elegante
        Container(
          width: 1,
          height: double.infinity,
          color: Colors.grey.shade100,
        ),

        // Lado Direito: Painel de Acesso Clean e direto ao ponto
        Expanded(
          flex: 3,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(60.0),
            child: Center(
              child: _buildLoginContent(context),
            ),
          ),
        ),
      ],
    );
  }

  // ── LAYOUT MOBILE ───────────────────────────────────────────────────────
  Widget _buildMobileLayout(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 80.0, horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          Image.asset(
            'assets/images/logo_branca.png',
            height: 160,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.monetization_on_outlined, size: 80, color: primaryOrange);
            },
          ),
          const SizedBox(height: 60),
          _buildLoginContent(context),
        ],
      ),
    );
  }

  // ── CONTEÚDO DO LOGIN (FORMULÁRIO / INFORMAÇÕES) ────────────────────────
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
          style: TextStyle(
            fontSize: 15,
            color: textGray,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 48),

        // Botão de Login Estilizado com Efeito de Sombra
        _buildMicrosoftButton(context),

        const SizedBox(height: 32),
        Center(
          child: TextButton(
            onPressed: () {
              // Ação opcional para abrir central de ajuda ou suporte TI
            },
            style: TextButton.styleFrom(
              foregroundColor: textGray,
            ),
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

  // ── BOTÃO MICROSOFT PERSONALIZADO (CORRIGIDO PARA ONTAPPED) ─────────────────────────
  Widget _buildMicrosoftButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: primaryOrange,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: primaryOrange.withOpacity(0.25),
            spreadRadius: 1,
            blurRadius: 12,
            offset: const Offset(0, 5), // Proporciona efeito de botão flutuante realçado
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () { // <-- CORRIGIDO AQUI: De onPressed para onTap
            // Executa a navegação direta simulando a autenticação com sucesso do Azure AD
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Ícone conceitual imitando a grade de serviços Microsoft
                Icon(Icons.widgets, size: 20, color: Colors.white.withOpacity(0.85)),
                const SizedBox(width: 10),
                const Icon(Icons.lock_open, size: 18, color: Colors.white),
                const SizedBox(width: 12),
                const Text(
                  'Entrar com Email Corporativo',
                  style: TextStyle(
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

  // ── FALLBACK PREMIUM (CASO A LOGO NÃO EXISTA NOS ASSETS) ────────────────
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