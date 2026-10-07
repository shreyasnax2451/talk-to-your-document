import 'package:flutter_test/flutter_test.dart';
import 'package:docchat/main.dart';

void main() {
  testWidgets('DocChatApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DocChatApp());
    await tester.pumpAndSettle();
    expect(find.text('DocChat'), findsNothing); // In drawer
    expect(find.byType(DocChatApp), findsOneWidget);
  });
}
