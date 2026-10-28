import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/model_config.dart';
import '../services/model_manager.dart';
import '../theme/app_theme.dart';

/// Lets the user pick the answering model. Shown on first launch and from the
/// profile menu. The model recommended for this phone's RAM is pre-selected.
class ModelSetupScreen extends StatefulWidget {
  /// First launch: no back button, and confirming continues into the app.
  final bool isFirstRun;

  const ModelSetupScreen({super.key, this.isFirstRun = false});

  @override
  State<ModelSetupScreen> createState() => _ModelSetupScreenState();
}

class _ModelSetupScreenState extends State<ModelSetupScreen> {
  double? _ramGb;
  bool _ramLoaded = false;
  ModelSpec? _selected;
  bool _wifiOnly = true;

  @override
  void initState() {
    super.initState();
    _selected = context.read<AppState>().answerModel;
    ModelConfig.deviceRamGb().then((ram) {
      if (!mounted) return;
      setState(() {
        _ramGb = ram;
        _ramLoaded = true;
        _selected ??= ModelConfig.recommendedFor(ram);
      });
    });
  }

  Future<void> _confirm() async {
    final model = _selected;
    if (model == null) return;
    final appState = context.read<AppState>();
    final navigator = Navigator.of(context);
    // Lets the download show progress in the notification shade (Android 13+).
    await FileDownloader().permissions.request(PermissionType.notifications);
    await appState.selectAnswerModel(model, wifiOnly: _wifiOnly);
    if (!widget.isFirstRun && navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final models = context.watch<ModelManager>();
    final current = context.watch<AppState>().answerModel;
    final recommended = ModelConfig.recommendedFor(_ramGb);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isFirstRun,
        title: const Text(
          'Answering model',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
        ),
      ),
      body: !_ramLoaded
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Text(
                  widget.isFirstRun
                      ? 'Choose the model that writes answers from your PDFs. It is '
                          'downloaded once and runs entirely on this phone. The download '
                          'continues in the background, so you can start adding documents now.'
                      : 'The model that writes answers from your PDFs. Switching downloads '
                          'the new model in the background; your documents stay indexed.',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 8),
                Text(
                  _ramGb == null
                      ? 'Could not read this phone\'s memory.'
                      : 'This phone has ${_ramGb!.round()} GB of RAM.',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                for (final model in ModelConfig.answeringModels) ...[
                  _ModelTile(
                    model: model,
                    state: models.stateOf(model),
                    isRecommended: model.id == recommended.id,
                    isSelected: model.id == _selected?.id,
                    isCurrent: model.id == current?.id,
                    onTap: () => setState(() => _selected = model),
                    onDelete: () => models.delete(model),
                    onRetry: () => models.download(model, wifiOnly: _wifiOnly),
                  ),
                  const SizedBox(height: 12),
                ],
                _SearchModelRow(state: models.stateOf(ModelConfig.embedding)),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppTheme.accent,
                  value: _wifiOnly,
                  onChanged: (v) => setState(() => _wifiOnly = v),
                  title: const Text('Download over Wi-Fi only',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                  subtitle: const Text('Recommended: models are 1-2.5 GB',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _selected == null ? null : _confirm,
            child: Text(
              _confirmLabel(models),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  String _confirmLabel(ModelManager models) {
    final model = _selected;
    if (model == null) return 'Continue';
    final ready = models.isReady(model);
    final action = ready ? 'Use' : 'Download';
    final suffix = widget.isFirstRun ? ' and continue' : '';
    return ready ? '$action ${model.displayName}$suffix' : '$action ${model.displayName} (${model.sizeLabel})$suffix';
  }
}

class _ModelTile extends StatelessWidget {
  final ModelSpec model;
  final ModelState state;
  final bool isRecommended;
  final bool isSelected;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRetry;

  const _ModelTile({
    required this.model,
    required this.state,
    required this.isRecommended,
    required this.isSelected,
    required this.isCurrent,
    required this.onTap,
    required this.onDelete,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? AppTheme.accent : AppTheme.border, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? AppTheme.accent : AppTheme.textMuted,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(model.displayName,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                      if (isRecommended)
                        const _Badge('Recommended', AppTheme.accentLight, AppTheme.accentSubtle),
                      if (isCurrent) const _Badge('In use', AppTheme.readyText, AppTheme.readyBg),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${model.sizeLabel} · for ${model.recommendedMinRamGb} GB+ RAM phones',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(model.description,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
                  const SizedBox(height: 8),
                  _StatusLine(state: state, onDelete: isCurrent ? null : onDelete, onRetry: onRetry),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final ModelState state;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;

  const _StatusLine({required this.state, this.onDelete, this.onRetry});

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case ModelStatus.notDownloaded:
        return const Text('Not downloaded', style: TextStyle(color: AppTheme.textMuted, fontSize: 12));
      case ModelStatus.downloading || ModelStatus.paused || ModelStatus.verifying:
        final label = switch (state.status) {
          ModelStatus.paused => 'Paused (waiting for network) · ${(state.progress * 100).round()}%',
          ModelStatus.verifying => 'Checking download…',
          _ => 'Downloading · ${(state.progress * 100).round()}%',
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppTheme.processingText, fontSize: 12)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.status == ModelStatus.verifying ? null : state.progress,
                minHeight: 4,
                color: AppTheme.processingText,
                backgroundColor: AppTheme.processingBg,
              ),
            ),
          ],
        );
      case ModelStatus.ready:
        return Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.readyText, size: 15),
            const SizedBox(width: 4),
            const Text('Downloaded', style: TextStyle(color: AppTheme.readyText, fontSize: 12)),
            const Spacer(),
            if (onDelete != null)
              TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, minimumSize: const Size(0, 28), foregroundColor: AppTheme.textSecondary),
                child: const Text('Delete', style: TextStyle(fontSize: 12)),
              ),
          ],
        );
      case ModelStatus.failed:
        return Row(
          children: [
            Expanded(
              child: Text(state.error ?? 'Download failed',
                  style: const TextStyle(color: AppTheme.failedText, fontSize: 12)),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, minimumSize: const Size(0, 28), foregroundColor: AppTheme.accent),
                child: const Text('Retry', style: TextStyle(fontSize: 12)),
              ),
          ],
        );
    }
  }
}

/// The search model is required and downloads automatically; shown for
/// transparency about what is on the phone.
class _SearchModelRow extends StatelessWidget {
  final ModelState state;

  const _SearchModelRow({required this.state});

  @override
  Widget build(BuildContext context) {
    const model = ModelConfig.embedding;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${model.displayName} · ${model.sizeLabel}',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Required. Downloads automatically.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          _StatusLine(state: state, onRetry: () => context.read<ModelManager>().download(model)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;

  const _Badge(this.label, this.fg, this.bg);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
