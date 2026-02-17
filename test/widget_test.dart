import 'package:flutter_test/flutter_test.dart';

import 'package:loki_psu/main.dart';

void main() {
  testWidgets('App renders scan screen', (WidgetTester tester) async {
    await tester.pumpWidget(const LokiPsuApp());
    await tester.pumpAndSettle();

    // Verify the scan screen title appears.
    expect(find.text('Loki PSU — Scan'), findsOneWidget);

    // Verify the scan FAB is present.
    expect(find.text('Scan'), findsOneWidget);
  });
}
