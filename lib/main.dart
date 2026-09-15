import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/driver/driver_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  runApp(const VitEvBuggyApp());
}

class VitEvBuggyApp extends StatelessWidget {
  const VitEvBuggyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VIT EV BUGGY',
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
      home: const DriverHomeScreen(),
    );
  }
}
