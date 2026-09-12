import 'package:flutter/material.dart';

import 'screens/faculty/faculty_home_screen.dart';

void main() {
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
