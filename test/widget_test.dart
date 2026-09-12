import 'package:flutter_test/flutter_test.dart';
import 'package:vit_ev_buggy/main.dart';

void main() {
  testWidgets('VIT EV BUGGY app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const VitEvBuggyApp());

    expect(find.text('VIT EV BUGGY'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);
  });
}
