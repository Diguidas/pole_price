import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pole_price/router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://jrumkdghuvuktjsdoknl.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpydW1rZGdodXZ1a3Rqc2Rva25sIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI2Nzg2MjksImV4cCI6MjEwODI1NDYyOX0.iY7Nb3UwoIFL2k52vvhlDJxyE9r73eHgkM5BOvUw-T4',
  );

  runApp(SistemaPrecoApp(router: criarRouter()));
}

class SistemaPrecoApp extends StatelessWidget {
  final GoRouter router;
  const SistemaPrecoApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: router,
      title: 'Pole Price',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F5F2),
        fontFamily: 'Poppins',
        primaryColor: const Color(0xFFE8793A), // Laranja Principal
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE8793A),
          primary: const Color(0xFFE8793A),
          secondary: const Color(0xFFD9682B),
          surface: Colors.white,
          background: const Color(0xFFF7F5F2), // Fundo cinza claro corporativo
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE8793A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}