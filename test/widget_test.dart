import 'package:flutter_test/flutter_test.dart';
import 'package:greggesmart/main.dart';

void main() {
  testWidgets('smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GreggeSmartApp());
  });
}
