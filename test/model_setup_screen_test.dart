import 'package:docchat/providers/app_state.dart';
import 'package:docchat/screens/model_setup_screen.dart';
import 'package:docchat/services/model_manager.dart';
import 'package:docchat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('lists both answering models with one Recommended badge', (tester) async {
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

    expect(find.text('Qwen3-4B'), findsOneWidget);
    expect(find.text('Qwen3-1.7B'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    // RAM is unknown in tests, so the smaller model is recommended and
    // pre-selected.
    expect(find.textContaining('Download Qwen3-1.7B'), findsOneWidget);

    await tester.tap(find.text('Qwen3-4B'));
    await tester.pump();
    expect(find.textContaining('Download Qwen3-4B (2.5 GB)'), findsOneWidget);
  });
}
