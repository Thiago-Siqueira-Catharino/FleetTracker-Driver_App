import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Uma classe simples para simular o usuário logado no Front
class UserSession {
  final String email;
  final String token;

  UserSession({required this.email, required this.token});
}

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

class LoginPage extends StatefulWidget {
  final Function(UserSession) onLoginSuccess;

  const LoginPage({super.key, required this.onLoginSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool loading = false;

  Future<void> loginComBackend() async {
    final url = Uri.parse('https://recess-mop-awoke.ngrok-free.dev/api/User/login'); 

    try {
      setState(() => loading = true);

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        }),
      );

      if (response.statusCode == 200) {
        //final data = jsonDecode(response.body);
        final String token = response.body; // Mapeie conforme a resposta da sua LoginUseCase

        final session = UserSession(
          email: _emailController.text.trim(),
          token: token,
        );

        widget.onLoginSuccess(session);
      } else {
        throw Exception("Usuário ou senha inválidos.");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro ao logar: $e")),
      );
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(labelText: 'Senha'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: loginComBackend,
                      child: const Text("Entrar"),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  final UserSession session;
  final VoidCallback onLogout;

  const HomePage({super.key, required this.session, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Painel do Carro"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: onLogout,
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.directions_car, size: 90, color: Colors.blue),
            const SizedBox(height: 20),
            Text(
              "Operador: ${session.email}",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              icon: const Icon(Icons.nfc),
              label: const Text("Simular Leitura NFC"),
              onPressed: () {
                // Aqui você vai disparar aquela lógica do nfc_manager que passei antes,
                // e para enviar a request de rota, você usará o 'session.token' no Header!
                print("Token guardado para usar no NFC: ${session.token}");
              },
            ),
          ],
        ),
      ),
    );
  }
}