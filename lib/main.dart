import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shell/cono_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(ConoOsApp(preferences: preferences));
}

class ConoOsApp extends StatelessWidget {
  const ConoOsApp({required this.preferences, super.key});

  final SharedPreferences preferences;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFE7E7E7);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: const Color(0xFF111111),
    );

    return MaterialApp(
      title: 'ConoOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFF080808),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: accent),
          ),
        ),
      ),
      home: ConoShell(preferences: preferences),
    );
  }
}
