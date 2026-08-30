import 'package:flutter_test/flutter_test.dart';
import 'package:telelearn/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TeleLearnApp());
    expect(find.byType(TeleLearnApp), findsOneWidget);
  });
}
