import 'package:flutter/material.dart';
import 'package:pole_price/screens/login_page.dart';
import 'package:pole_price/widgets/auth_guard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://jrumkdghuvuktjsdoknl.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpydW1rZGdodXZ1a3Rqc2Rva25sIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI2Nzg2MjksImV4cCI6MjEwODI1NDYyOX0.iY7Nb3UwoIFL2k52vvhlDJxyE9r73eHgkM5BOvUw-T4',
  );

  runApp(const SistemaPrecoApp());
}

class SistemaPrecoApp extends StatelessWidget {
  const SistemaPrecoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pole Price',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Poppins',
        primaryColor: const Color(0xFFFF6B00), // Laranja Principal
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B00),
          primary: const Color(0xFFFF6B00),
          secondary: const Color(0xFFE05300),
          surface: Colors.white,
          background: const Color(0xFFF8F9FA), // Fundo cinza claro corporativo
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B00),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: Supabase.instance.client.auth.currentSession != null
          ? const AuthGuard()
          : const LoginPage(),
    );
  }
}