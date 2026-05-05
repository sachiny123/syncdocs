import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const ColabDocsApp());
}

class ColabDocsApp extends StatelessWidget {
  const ColabDocsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Colab Docs',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF6C63FF),
          surface: const Color(0xFF1A1D2E),
          background: const Color(0xFF0F1117),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        fontFamily: 'sans-serif',
      ),
      home: const LoginScreen(),
    );
  }
}
