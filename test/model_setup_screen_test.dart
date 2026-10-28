import 'package:docchat/providers/app_state.dart';
import 'package:docchat/screens/model_setup_screen.dart';
import 'package:docchat/services/model_manager.dart';
import 'package:docchat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('shows user-facing model names, one Recommended badge and a Download button',
      (tester) async {
    final models = ModelManager(); // not started: no platform channels in tests
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: models),
        ChangeNotifierProvider(create: (_) => AppState(models)),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const ModelSetupScreen(isFirstRun: true),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('High accuracy'), findsOneWidget);
    expect(find.text('Basic'), findsOneWidget);
    expect(find.textContaining('Default resources pack'), findsOneWidget);
    expect(find.textContaining('Qwen'), findsNothing);
    expect(find.textContaining('EmbeddingGemma'), findsNothing);
    expect(find.text('Recommended'), findsOneWidget);

    final button = find.widgetWithText(ElevatedButton, 'Download');
    expect(button, findsOneWidget);
    // A model is pre-selected and not downloading, so the button is enabled.
    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
  });
}
