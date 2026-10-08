import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/admin/admin_home_screen.dart';

/// Starts the Admin app and prepares Firebase.
Future<void> main() async {
  // Required before Firebase is initialized.
  WidgetsFlutterBinding.ensureInitialized();

  // Connects the Admin app to the Firebase project.
  await Firebase.initializeApp();

  runApp(const EvBuggyAdminApp());
}

/// Main app widget for the EV Buggy Admin dashboard.
class EvBuggyAdminApp extends StatelessWidget {
  const EvBuggyAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Opens the Admin dashboard as the first screen.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EV Buggy Admin',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F2C56),
        ),
        useMaterial3: true,
      ),
      home: const AdminHomeScreen(),
    );
  }
}