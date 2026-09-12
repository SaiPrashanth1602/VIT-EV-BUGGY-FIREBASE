import 'package:flutter/material.dart';

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
      home: Scaffold(
        appBar: AppBar(title: const Text('VIT EV BUGGY')),
        body: const Center(child: Text('Driver Module')),
      ),
    );
  }
}
