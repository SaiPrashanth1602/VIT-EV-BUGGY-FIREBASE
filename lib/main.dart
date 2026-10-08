import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'screens/faculty/faculty_home_screen.dart';

/// Starts the faculty app and prepares Flutter services.
Future<void> main() async {
  // Required before Firebase is initialized.
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is used only on supported mobile and desktop platforms.
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Allow the app to open even if Firebase is not available.
    }
  }

  runApp(const VitEvBuggyFacultyApp());
}

/// Main app widget for the faculty EV tracking app.
class VitEvBuggyFacultyApp extends StatelessWidget {
  const VitEvBuggyFacultyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Opens the faculty dashboard as the first screen.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VIT EV BUGGY',
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
      home: const FacultyHomeScreen(),
    );
  }
}
