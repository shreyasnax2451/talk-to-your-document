import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/model_setup_screen.dart';
import '../services/model_manager.dart';
import '../theme/app_theme.dart';

/// A slim progress strip shown while models download in the background.
/// Tapping it opens the model screen.
///
/// Shows one combined figure for everything downloading (weighted by size),
/// rather than switching between items, so the percentage only moves forward.
class ModelDownloadBanner extends StatelessWidget {
  const ModelDownloadBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final models = context.watch<ModelManager>();
    final active = models.activeDownloads;
    if (active.isEmpty) return const SizedBox.shrink();

    final batch = models.downloadBatch;
    final percent = (models.batchProgress * 100).floor();
    final what = batch.length == 1 ? batch.single.displayName : '${batch.length} downloads';
    final states = [for (final m in active) models.stateOf(m).status];
    final allVerifying = states.every((s) => s == ModelStatus.verifying);
    final paused = states.contains(ModelStatus.paused);
    final label = allVerifying
        ? 'Checking ${active.length == 1 ? active.single.displayName : 'downloads'}…'
        : paused
            ? 'Downloading $what · $percent% · paused, waiting for network'
            : 'Downloading $what · $percent%';

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
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.processingText, fontSize: 12),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: allVerifying ? null : models.batchProgress,
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
