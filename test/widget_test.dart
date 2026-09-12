import 'package:flutter_test/flutter_test.dart';
import 'package:vit_ev_buggy/main.dart';

void main() {
  testWidgets('VIT EV BUGGY Faculty app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const VitEvBuggyFacultyApp());

    expect(find.text('VIT EV BUGGY'), findsOneWidget);
    expect(find.text('Faculty'), findsOneWidget);
  });
}
