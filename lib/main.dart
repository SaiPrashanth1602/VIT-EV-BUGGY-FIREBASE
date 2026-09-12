import 'package:flutter/material.dart';

import 'screens/driver/driver_home_screen.dart';

void main() {
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
