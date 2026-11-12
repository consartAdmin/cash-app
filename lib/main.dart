import 'package:flutter/material.dart';

import 'api_service.dart';
import 'home_page.dart';
import 'login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.instance.load();
  runApp(const CaixaApp());
}

ThemeData _theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF089FD2),
        brightness: b,
      ),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );

class CaixaApp extends StatelessWidget {
  const CaixaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CONSART Caixa',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home:
          ApiService.instance.isLoggedIn ? const HomePage() : const LoginPage(),
    );
  }
}
