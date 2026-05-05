import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_flutter/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ColabDocsApp());
    // The app starts on LoginScreen — just verify it builds without error
    expect(find.text('Colab Docs'), findsWidgets);
  });
}
