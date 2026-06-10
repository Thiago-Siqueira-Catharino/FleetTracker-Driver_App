import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import 'dart:convert';
import 'dart:async';
import 'usersession.dart';
import 'locationservice.dart';
//import 'leitorobd.dart';

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
  //late final _leitorOdb;
  late final _locationService;
  
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
  Future<String?> _tentarLerNfcFisico() async {
    print("iniciando leitura da tag");
    NfcAvailability isAvailable = await NfcManager.instance.checkAvailability();

    if (isAvailable != NfcAvailability.enabled) {
      throw Exception("Falha na leitura da tag. Leitor NFC desabilitado ou faltando");
    }

    final completer = Completer<String?>();

    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443}, 
      onDiscovered: (NfcTag tag) async {
        List<int>? rawBytes;

        final nfca = NfcAAndroid.from(tag);

        if (nfca != null) {
          rawBytes = nfca.tag.id;
        }

        if (rawBytes != null) {
          final String hex = rawBytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
          if (!completer.isCompleted) {
            completer.complete(hex);
            await NfcManager.instance.stopSession();
          } else {
            await NfcManager.instance.stopSession();
          }
        }
      }
    );

    return completer.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () async {
        print("nenhuma tag encontrada");
        await NfcManager.instance.stopSession();
        return null;
      }
    ); 
  }

  Future<void> _iniciarNovoCaminhoNoBackend(String tagUid) async {
    print("iniciando novo caminho");
    final url = Uri.parse('https://recess-mop-awoke.ngrok-free.dev/api/Path');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.session.token}', // JWT do Header!
          'ngrok-skip-browser-warning': '1' 
        },
        body: jsonEncode({'tagId': tagUid}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        //backend precisa retornar o ID criado no corpo da resposta
        final data = jsonDecode(response.body);
        setState(() {
          _idCaminhoAtivo = data.replaceAll('"', ''); // Ex: Guid retornado pelo C#
        });
        print("Novo trajeto iniciado no Back com ID: $_idCaminhoAtivo");
      }
    } catch (e) {
      print("Erro ao criar caminho: $e");
    }
  }

  Future<void> _enviarPontoTelemetria() async {
    print("caminho encontrado, atualizando localização");
    if (_idCaminhoAtivo == null) return;

    final url = Uri.parse('https://recess-mop-awoke.ngrok-free.dev/api/LocationPoint/location/update');
    
    try {
      var posicao = await _locationService.determinarPosicao();
      double latitude = posicao.latitude; 
      double longitude = posicao.longitude;
      double speed = posicao.speed;
      String ISODataHora = DateTime.now().toUtc().toIso8601String();
      //double combustivel = await _leitorOdb.ObterCombustivel();

      await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.session.token}',
          'ngrok-skip-browser-warning': '1' 
        },
        body: jsonEncode({
          'PathId': _idCaminhoAtivo,
          'Latitude': latitude,
          'Longitude': longitude,
          'Timestamp': ISODataHora,
          'FuelLevel': 0,
          'Speed': speed 
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
  void initState() {
    super.initState();
      //_leitorOdb = LeitorOdb();
      _locationService = LocationService();
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