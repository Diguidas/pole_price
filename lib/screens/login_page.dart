import 'package:flutter/material.dart';
import 'package:pole_price/screens/home_screen.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Lado Esquerdo: Banner Laranja
          Expanded(
            flex: 4,
            child: Container(
              color: Theme.of(context).primaryColor,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.monetization_on_outlined, size: 80, color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Pole Price',
                      style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Lado Direito: Painel de Acesso
          Expanded(
            flex: 3,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(48.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Bem-vindo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Acesse o Portal com sua conta Microsoft corporativa.'),
                    const SizedBox(height: 40),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Entrar com Email Corporativo', style: TextStyle(fontSize: 16)),
                      onPressed: () {
                        // Navega direto para a HomeScreen simulando o sucesso do Azure AD
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const HomeScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}