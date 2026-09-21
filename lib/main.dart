import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'screens/faculty/faculty_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Keep the UI responsive even when Firebase is unavailable during tests or
      // a partially configured startup environment.
    }
  }

  runApp(const VitEvBuggyFacultyApp());
}

class VitEvBuggyFacultyApp extends StatelessWidget {
  const VitEvBuggyFacultyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VIT EV BUGGY',
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
      home: const FacultyHomeScreen(),
    );
  }
}
