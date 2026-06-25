import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/app_theme.dart';
import 'driver_app.dart';
import 'register_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});
  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final String? driverId = prefs.getString('driver_id');
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    if (driverId != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DriverApp()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const RegisterScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
        backgroundColor: AppTheme.primary,
        body: Center(child: CircularProgressIndicator(color: AppTheme.textLight))
    );
  }
}