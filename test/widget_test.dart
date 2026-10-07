import 'package:flutter_test/flutter_test.dart';
import 'package:vit_ev_buggy_admin/main.dart';

void main() {
  testWidgets('Admin app launches', (WidgetTester tester) async {
    await tester.pumpWidget(const EvBuggyAdminApp());

    expect(find.text('EV Buggy Admin'), findsOneWidget);
  });
}