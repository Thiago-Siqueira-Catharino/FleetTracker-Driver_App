import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'usersession.dart';
import 'homepage.dart';
import 'loginpage.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  UserSession? _session;
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _loadSession(); // Verifica se já tem login salvo ao abrir o app
  }

  // Carrega o token do disco se existir
  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('jwt_token');
    final String? email = prefs.getString('user_email');

    if (token != null && email != null) {
      setState(() {
        _session = UserSession(email: email, token: token);
      });
    }
    setState(() => _checkingSession = false);
  }

  // Salva os dados quando o login dá certo
  Future<void> _onLoginSuccess(UserSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', session.token);
    await prefs.setString('user_email', session.email);

    setState(() {
      _session = session;
    });
  }

  // Limpa tudo no logout
  Future<void> _onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_email');

    setState(() {
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Enquanto lê o disco, mostra uma tela de carregamento neutra
    if (_checkingSession) {
      return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _session != null 
          ? HomePage(session: _session!, onLogout: _onLogout) 
          : LoginPage(onLoginSuccess: _onLoginSuccess),
    );
  }
}