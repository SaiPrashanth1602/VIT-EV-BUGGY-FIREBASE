import 'package:flutter/material.dart';

import 'screens/faculty/faculty_home_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.instance.initialize();

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
