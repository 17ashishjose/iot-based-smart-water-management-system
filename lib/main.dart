import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://rpumtokaszpqwkscungk.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwdW10b2thc3pwcXdrc2N1bmdrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3Mzc3MTAsImV4cCI6MjA4OTMxMzcxMH0.-bhyXpGhZoCNQ11xxMPxA8_1qqVI2WLY_N7VbUOOejo',
  );

  runApp(const WaterManagerApp());
}

class WaterManagerApp extends StatelessWidget {
  const WaterManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Water Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D4FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}