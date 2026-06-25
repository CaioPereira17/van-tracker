import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/theme/app_theme.dart';
import 'driver_app.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _plateController = TextEditingController();
  final _seatsController = TextEditingController();

  Future<void> _saveDriver() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      String newId = const Uuid().v4();
      await prefs.setString('driver_id', newId);
      await prefs.setString('driver_name', _nameController.text);
      await prefs.setString('vehicle_plate', _plateController.text);
      await prefs.setString('vehicle_seats', _seatsController.text);

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DriverApp()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text("Cadastro"), backgroundColor: AppTheme.primary, foregroundColor: AppTheme.textLight),
        body: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
                key: _formKey,
                child: Column(children: [
                  const Icon(Icons.directions_bus, size: 80, color: AppTheme.primary),
                  const SizedBox(height: 20),
                  TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: "Nome"), validator: (v)=>v!.isEmpty?"Erro":null),
                  const SizedBox(height: 15),
                  TextFormField(controller: _plateController, decoration: const InputDecoration(labelText: "Modelo"), validator: (v)=>v!.isEmpty?"Erro":null),
                  const SizedBox(height: 15),
                  TextFormField(controller: _seatsController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Lugares"), validator: (v)=>v!.isEmpty?"Erro":null),
                  const SizedBox(height: 30),
                  SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                          onPressed: _saveDriver,
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.textLight),
                          child: const Text("SALVAR")
                      )
                  )
                ])
            )
        )
    );
  }
}