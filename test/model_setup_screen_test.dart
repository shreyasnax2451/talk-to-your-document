import 'package:docchat/providers/app_state.dart';
import 'package:docchat/screens/model_setup_screen.dart';
import 'package:docchat/services/model_config.dart';
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

  testWidgets('the choice is locked while a model downloads', (tester) async {
    final models = _DownloadingModels(ModelConfig.qwen3_4b);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ModelManager>.value(value: models),
        ChangeNotifierProvider(create: (_) => AppState(models)),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const ModelSetupScreen(isFirstRun: true),
      ),
    ));
    await tester.pumpAndSettle();

    bool isChecked(String title) => tester
        .widgetList<Icon>(find.descendant(
          of: find.ancestor(of: find.text(title), matching: find.byType(Row)).last,
          matching: find.byType(Icon),
        ))
        .any((i) => i.icon == Icons.radio_button_checked_rounded);

    // The downloading model is shown as selected, even though RAM is unknown
    // in tests (which would otherwise pre-select Basic).
    expect(isChecked('High accuracy'), isTrue);

    await tester.tap(find.text('Basic'));
    await tester.pump();
    expect(isChecked('High accuracy'), isTrue);
    expect(isChecked('Basic'), isFalse);

    final button = find.widgetWithText(ElevatedButton, 'Download');
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
    await tester.scrollUntilVisible(find.byType(SwitchListTile), 200);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
  });
}

/// [model] is mid-download; everything else is not downloaded.
class _DownloadingModels extends ModelManager {
  final ModelSpec model;
  _DownloadingModels(this.model);

  @override
  ModelState stateOf(ModelSpec m) => m.id == model.id
      ? const ModelState(ModelStatus.downloading, progress: 0.4)
      : const ModelState(ModelStatus.notDownloaded);
}
