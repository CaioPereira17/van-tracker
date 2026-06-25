import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

// Imports internos
import '../core/theme/app_theme.dart';
import '../core/utils/map_styles.dart';
import 'register_screen.dart';

class DriverApp extends StatefulWidget {
  const DriverApp({super.key});

  @override
  State<DriverApp> createState() => _DriverAppState();
}

class _DriverAppState extends State<DriverApp> with WidgetsBindingObserver {
  late IO.Socket socket;
  String connectionStatus = "Conectando...";

  bool isDarkMap = false;
  GoogleMapController? _googleMapController;
  final Completer<GoogleMapController> _mapController = Completer();

  String driverName = "Motorista";
  String driverPlate = "...";
  String driverId = "";

  bool _ecoMode = false; // Começa vendo o mapa, mas pode trocar

  bool isRunning = false;
  bool isLunching = false;

  LatLng _currentPosition = const LatLng(-22.931173, -43.179873);
  final List<LatLng> _routePath = [];
  final Set<Polyline> _polylines = {};

  StreamSubscription<Position>? _positionStream;
  Timer? _stopwatchTimer;
  int _secondsWorked = 0;

  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDriverInfo();
    _loadHistory();
    initSocket();
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _stopwatchTimer?.cancel();
    socket.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      final service = FlutterBackgroundService();
      service.invoke("stopService");
    }
  }

  void _toggleMapTheme() {
    setState(() {
      isDarkMap = !isDarkMap;
    });

    if (_googleMapController != null) {
      if (isDarkMap) {
        // Usando a classe utilitária que criamos
        _googleMapController!.setMapStyle(MapStyles.dark);
      } else {
        _googleMapController!.setMapStyle(null);
      }
    }
  }

  Future<void> _loadDriverInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      driverName = prefs.getString('driver_name') ?? "Motorista";
      driverPlate = prefs.getString('vehicle_plate') ?? "Van";
      driverId = prefs.getString('driver_id') ?? "unknown_id";
    });
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyJson = prefs.getString('trip_history');
    if (historyJson != null) {
      setState(
        () => _history = List<Map<String, dynamic>>.from(
          json.decode(historyJson),
        ),
      );
    }
  }

  Future<void> _saveToHistory(String duration) async {
    final now = DateTime.now();
    String dateStr =
        "${now.day}/${now.month} - ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
    final newEntry = {
      "data": dateStr,
      "duracao": duration,
      "rota": "Rota Pereira",
    };
    setState(() => _history.insert(0, newEntry));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('trip_history', json.encode(_history));
  }

  String get formattedTime {
    int hours = _secondsWorked ~/ 3600;
    int minutes = (_secondsWorked % 3600) ~/ 60;
    int seconds = _secondsWorked % 60;
    return "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  void initSocket() {
    const String ipDoComputador =
        'IP_LOCAL_DO_SEU_PC'; // Substitua pelo IP do seu computador na rede local
    String backendUrl = Platform.isAndroid
        ? 'http://$ipDoComputador:3000'
        : 'http://localhost:3000';

    socket = IO.io(
      backendUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );
    socket.connect();
    socket.onConnect((_) => setState(() => connectionStatus = "Online 🟢"));
    socket.onDisconnect((_) {
      setState(() => connectionStatus = "Offline 🔴");

      // MOSTRAR AVISO VISUAL
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Conexão perdida! Tentando reconectar..."),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  Future<void> _checkPermissions() async {
    await Geolocator.requestPermission();
  }

  void startTracking() async {
    final service = FlutterBackgroundService();
    var isRunningService = await service.isRunning();
    if (!isRunningService) {
      service.startService();
    }

    setState(() {
      isRunning = true;
      isLunching = false;
      _secondsWorked = 0;
      _routePath.clear();
      _polylines.clear();
    });

    _stopwatchTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) => setState(() => _secondsWorked++),
    );

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) async {
            if (mounted && _mapController.isCompleted) {
              try {
                final GoogleMapController controller =
                    await _mapController.future;
                controller.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(
                      target: LatLng(position.latitude, position.longitude),
                      zoom: 17.0,
                      tilt: 0.0,
                      bearing: position.heading,
                    ),
                  ),
                );
              } catch (e) {
                // ...
              }
            }

            if (mounted) {
              setState(
                () => _currentPosition = LatLng(
                  position.latitude,
                  position.longitude,
                ),
              );
            }

            if (!isLunching) {
              _routePath.add(LatLng(position.latitude, position.longitude));
              _polylines.add(
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: _routePath,
                  color: Colors.blue,
                  width: 5,
                ),
              );
            }

            Map<String, dynamic> dados = {
              "van_id": driverId,
              "driver_name": driverName,
              "vehicle_plate": driverPlate,
              "lat": position.latitude,
              "lng": position.longitude,
              "status": isLunching ? "lunch" : "active",
            };
            socket.emit('update_location', dados);
          },
        );
  }

  void toggleLunch() {
    if (!isRunning) return;

    setState(() => isLunching = !isLunching);

    Map<String, dynamic> dados = {
      "van_id": driverId,
      "driver_name": driverName,
      "vehicle_plate": driverPlate,
      "lat": _currentPosition.latitude,
      "lng": _currentPosition.longitude,
      "status": isLunching ? "lunch" : "active",
    };

    socket.emit('update_location', dados);
  }

  void stopTracking() {
    _saveToHistory(formattedTime);
    _positionStream?.cancel();
    _stopwatchTimer?.cancel();

    final service = FlutterBackgroundService();
    service.invoke("stopService");

    socket.emit('stop_run', {"van_id": driverId});

    setState(() {
      isRunning = false;
      isLunching = false;
      _secondsWorked = 0;
      _routePath.clear();
      _polylines.clear();
    });
  }

  Future<void> _logout() async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Sair?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Sim"),
              ),
            ],
          ),
        ) ??
        false;
    if (confirm) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const RegisterScreen()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Portal do Motorista",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                driverName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
          ],
          backgroundColor: AppTheme.primary,
          foregroundColor: AppTheme.textLight,
          bottom: const TabBar(
            indicatorColor: AppTheme.textLight,
            labelColor: AppTheme.textLight,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: Icon(Icons.navigation), text: "Rota"),
              Tab(icon: Icon(Icons.history), text: "Histórico"),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            Stack(
              children: [
                // -------------------------------------------------------
                // CAMADA 1: O MAPA (Fundo)
                // -------------------------------------------------------
                Positioned.fill(
                  child: isMobile
                      ? GoogleMap(
                          mapType: MapType.normal,
                          initialCameraPosition: CameraPosition(
                            target: _currentPosition,
                            zoom: 18,
                            tilt: 0.0,
                          ),
                          myLocationEnabled: true,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          compassEnabled: true,
                          polylines: _polylines,
                          onMapCreated: (c) {
                            _googleMapController = c;
                            if (!_mapController.isCompleted)
                              _mapController.complete(c);
                          },
                        )
                      : Container(color: Colors.grey[200]),
                ),

                // -------------------------------------------------------
                // CAMADA 2: INTERFACE DE USUÁRIO (Painel e Tema)
                // (Ficam abaixo da tela preta de economia)
                // -------------------------------------------------------

                // Botão de Tema
                Positioned(
                  top: 20,
                  right: 20,
                  child: FloatingActionButton.small(
                    heroTag: "theme_toggle",
                    backgroundColor: isDarkMap ? Colors.black87 : Colors.white,
                    foregroundColor: isDarkMap ? Colors.amber : Colors.blueGrey,
                    onPressed: _toggleMapTheme,
                    child: Icon(
                      isDarkMap ? Icons.wb_sunny : Icons.nightlight_round,
                    ),
                  ),
                ),

                // Painel Inferior (Status e Ações)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(25),
                        topRight: Radius.circular(25),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 20,
                          offset: Offset(0, -5),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Linha de Status e Hora
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "STATUS",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      connectionStatus,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  formattedTime,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    color: AppTheme.textDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // Botões de Ação (Almoço e Iniciar)
                            Row(
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: ElevatedButton(
                                    onPressed: isRunning ? toggleLunch : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isLunching
                                          ? AppTheme.btnLunch
                                          : AppTheme.btnDisabled,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 15,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Column(
                                      children: [
                                        Icon(Icons.restaurant),
                                        Text(
                                          "Almoço",
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 15),
                                Expanded(
                                  flex: 2,
                                  child: ElevatedButton(
                                    onPressed: isRunning
                                        ? stopTracking
                                        : startTracking,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isRunning
                                          ? AppTheme.btnStop
                                          : AppTheme.btnStart,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 15,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          isRunning
                                              ? Icons.stop_circle_outlined
                                              : Icons.play_circle_fill,
                                          size: 28,
                                          color: Colors.white,
                                        ),
                                        Text(
                                          isRunning
                                              ? "ENCERRAR"
                                              : "INICIAR ROTA",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // -------------------------------------------------------
                // CAMADA 3: OVERLAY DE ECONOMIA
                // (Cobre mapa e painel, mas não o botão de sair do modo eco)
                // -------------------------------------------------------
                if (_ecoMode)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black, // Fundo preto total
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isRunning ? Icons.wifi_tethering : Icons.wifi_off,
                            size: 80,
                            color: isRunning ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            isRunning ? "RASTREAMENTO\nATIVO" : "AGUARDANDO...",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isRunning ? Colors.green : Colors.white54,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 30),
                          Text(
                            connectionStatus,
                            style: TextStyle(
                              color: connectionStatus.contains("Online")
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 50),
                          const Text(
                            "Toque no ícone de bateria\npara ver o mapa",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white24,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // -------------------------------------------------------
                // CAMADA 4: BOTÃO TOGGLE ECO MODE (Topo Absoluto)
                // -------------------------------------------------------
                Positioned(
                  top: 80,
                  right: 20,
                  child: FloatingActionButton.small(
                    heroTag: "eco_mode",
                    backgroundColor: _ecoMode ? Colors.green : Colors.white,
                    onPressed: () {
                      setState(() {
                        _ecoMode = !_ecoMode;
                      });
                    },
                    child: Icon(
                      _ecoMode ? Icons.visibility_off : Icons.battery_saver,
                      color: _ecoMode ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            Container(
              color: AppTheme.background,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      "Minhas Viagens",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _history.isEmpty
                        ? const Center(
                            child: Text("Nenhuma corrida registrada."),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(10),
                            itemCount: _history.length,
                            itemBuilder: (context, index) {
                              final item = _history[index];
                              return Card(
                                elevation: 2,
                                color: AppTheme.cardBackground,
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.history,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  title: Text(
                                    item['rota'] ?? "Rota",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(item['data'] ?? ""),
                                  trailing: Text(
                                    item['duracao'] ?? "00:00",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
