import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vit_ev_buggy/main.dart';

void main() {
  testWidgets('VIT EV BUGGY Faculty app loads', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Ignore Firebase initialization failures in test environments without a
      // generated config.
    }

    await tester.pumpWidget(const VitEvBuggyFacultyApp());

    expect(find.text('VIT EV BUGGY'), findsOneWidget);
    expect(find.text('Faculty Shuttle Tracking'), findsOneWidget);
  });
}
