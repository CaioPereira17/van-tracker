import 'package:flutter/material.dart';
// Importe o serviço e a tela inicial
import 'services/background_service.dart';
import 'screens/loading_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService(); // Inicializa o serviço separado
  runApp(const MaterialApp(home: LoadingScreen(), debugShowCheckedModeBanner: false));
}