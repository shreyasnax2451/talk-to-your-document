import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/model_setup_screen.dart';
import '../services/model_manager.dart';
import '../theme/app_theme.dart';

/// A slim progress strip shown while models download in the background.
/// Tapping it opens the model screen.
class ModelDownloadBanner extends StatelessWidget {
  const ModelDownloadBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final models = context.watch<ModelManager>();
    final active = models.activeDownloads;
    if (active.isEmpty) return const SizedBox.shrink();

    final model = active.first;
    final state = models.stateOf(model);
    final label = switch (state.status) {
      ModelStatus.verifying => 'Checking ${model.displayName}…',
      ModelStatus.paused => '${model.displayName} paused, waiting for network · ${(state.progress * 100).round()}%',
      _ => 'Downloading ${model.displayName} · ${(state.progress * 100).round()}%',
    };

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ModelSetupScreen()),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        color: AppTheme.processingBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              active.length > 1 ? '$label  (+${active.length - 1} more)' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.processingText, fontSize: 12),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: state.status == ModelStatus.verifying ? null : state.progress,
                minHeight: 3,
                color: AppTheme.processingText,
                backgroundColor: AppTheme.processingBorder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
