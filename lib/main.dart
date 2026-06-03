import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

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

class HomePage extends StatefulWidget {
  final UserSession session;
  final VoidCallback onLogout;

  const HomePage({super.key, required this.session, required this.onLogout});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _telemetryTimer;
  bool _isTracking = false;
  
  // Variáveis de controle do fluxo
  String? _idCaminhoAtivo;
  int _leiturasFalhas = 0;

  // 1. Inicia o Loop de 5 segundos
  void startTracking() {
    setState(() {
      _isTracking = true;
      _idCaminhoAtivo = null;
      _leiturasFalhas = 0;
    });

    _telemetryTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _processarCicloTelemetria();
    });
  }

  // 2. Para o Loop
  void stopTracking() {
    _telemetryTimer?.cancel();
    setState(() {
      _isTracking = false;
      _idCaminhoAtivo = null;
    });
  }

  // 3. O coração da lógica a cada 5 segundos
  Future<void> _processarCicloTelemetria() async {
    // Substitua pela sua chamada real do hardware do NFC
    String? tagUidDetectada = await _tentarLerNfcFisico(); 

    if (tagUidDetectada != null) {
      // SUCESSO: Leu a tag
      _leiturasFalhas = 0; 

      if (_idCaminhoAtivo == null) {
        // Cenário A: Primeiro ponto, cria o caminho no back
        await _iniciarNovoCaminhoNoBackend(tagUidDetectada);
      } else {
        // Cenário B: Caminho já existe, envia ponto de telemetria
        await _enviarPontoTelemetria();
      }
    } else {
      // FALHA: Não detectou nenhuma tag perto do leitor
      _leiturasFalhas++;
      print("Tag não detectada. Falhas seguidas: $_leiturasFalhas");

      if (_leiturasFalhas >= 2) {
        print("Perda de sinal confirmada (2 falhas). Finalizando trajeto local.");
        // Reseta o ID. No próximo ciclo que ler uma tag, iniciará um NOVO caminho
        setState(() {
          _idCaminhoAtivo = null; 
        });
      }
    }
  }

  // --- MÉTODOS DE SUPORTE (API E SENSORES) ---

  // Função fictícia para simular a leitura do NFC do aparelho
  Future<String?> _tentarLerNfcFisico() async {
    // Ler a NFC, tá essa bomba ainda
    return "04:A1:B2:C3:D4:E5:F6"; 
  }

  Future<void> _iniciarNovoCaminhoNoBackend(String tagUid) async {
    final url = Uri.parse('https://recess-mop-awoke.ngrok-free.dev/api/Path');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.session.token}' // JWT do Header!
        },
        body: jsonEncode({'tagUid': tagUid}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        //backend precisa retornar o ID criado no corpo da resposta
        final data = jsonDecode(response.body);
        setState(() {
          _idCaminhoAtivo = data['id']; // Ex: Guid retornado pelo C#
        });
        print("Novo trajeto iniciado no Back com ID: $_idCaminhoAtivo");
      }
    } catch (e) {
      print("Erro ao criar caminho: $e");
    }
  }

  Future<void> _enviarPontoTelemetria() async {
    if (_idCaminhoAtivo == null) return;

    final url = Uri.parse('https://recess-mop-awoke.ngrok-free.dev/api/LocationPoint/update');
    
    //Substituir pelo Geolocator
    double latitude = -22.6142; 
    double longitude = -50.5973;
    String ISODataHora = DateTime.now().toUtc().toIso8601String();

    try {
      await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.session.token}'
        },
        body: jsonEncode({
          'pathId': _idCaminhoAtivo,
          'latitude': latitude,
          'longitude': longitude,
          'timestamp': ISODataHora
        }),
      );
      print("Ponto enviado com sucesso para o caminho $_idCaminhoAtivo");
    } catch (e) {
      print("Erro ao enviar ponto: $e");
    }
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel(); // Garante que o timer morre se sairmos da tela
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Painel de Monitoramento")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isTracking ? Icons.gpp_good : Icons.gpp_maybe,
              size: 100,
              color: _isTracking ? Colors.green : Colors.red,
            ),
            const SizedBox(height: 20),
            Text("Status: ${_isTracking ? 'Rastreando' : 'Desativado'}" ),
            if (_idCaminhoAtivo != null) Text("ID Rota: $_idCaminhoAtivo"),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isTracking ? stopTracking : startTracking,
              child: Text(_isTracking ? "Parar Serviço" : "Iniciar Serviço"),
            )
          ],
        ),
      ),
    );
  }
}