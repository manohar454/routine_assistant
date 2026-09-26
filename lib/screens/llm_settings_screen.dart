import 'package:flutter/material.dart';
import '../services/llm_service.dart';
import '../theme/app_theme.dart';

/// Settings screen for the on-device AI model.
///
/// Shows download status and lets the user trigger the ~1GB model download.
/// The model is optional — the app works fully without it, with rule-based
/// fallbacks for preference extraction and no reasoning trace explanations.
class LlmSettingsScreen extends StatefulWidget {
  const LlmSettingsScreen({super.key});

  @override
  State<LlmSettingsScreen> createState() => _LlmSettingsScreenState();
}

class _LlmSettingsScreenState extends State<LlmSettingsScreen> {
  double? _progress; // null = idle, 0.0–1.0 = downloading
  String? _error;

  bool get _isReady => LlmService.instance.isReady;
  bool get _isLoading => LlmService.instance.isLoading;

  Future<void> _download() async {
    setState(() {
      _progress = 0.0;
      _error = null;
    });

    try {
      await LlmService.instance.loadModel(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) setState(() => _progress = null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final text = context.text;
    final ink = dark ? AppColors.darkInk : AppColors.ink;
    final sub = dark ? AppColors.darkInkSubtle : AppColors.inkSubtle;
    final card = dark ? AppColors.darkCard : AppColors.cardSurface;
    final accent = dark ? AppColors.darkDeep : AppColors.deep;

    return Scaffold(
      backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
      appBar: AppBar(
        backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('On-device AI',
            style: text.titleMedium?.copyWith(
                color: ink, fontWeight: FontWeight.w600)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: card,
                borderRadius: const BorderRadius.all(AppRadius.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isReady
                            ? Icons.check_circle_rounded
                            : Icons.cloud_download_rounded,
                        color: _isReady ? Colors.green : accent,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isReady
                            ? 'Model ready'
                            : _isLoading
                                ? 'Downloading…'
                                : 'Model not downloaded',
                        style: text.titleSmall
                            ?.copyWith(color: ink, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gemma 3 1B — ~1 GB download\n'
                    'Runs fully on-device. Powers smart preference extraction '
                    'and plain-language explanations for every scheduling decision.',
                    style: text.bodySmall?.copyWith(color: sub),
                  ),
                  if (_progress != null) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        backgroundColor:
                            (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)
                                .withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation(accent),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${(_progress! * 100).toStringAsFixed(0)}%',
                      style: text.labelSmall?.copyWith(color: sub),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Download failed. Check your internet connection and try again.\n$_error',
                      style: text.bodySmall
                          ?.copyWith(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // What the AI powers
            Text('What it powers',
                style: text.labelMedium
                    ?.copyWith(color: sub, letterSpacing: 0.5)),
            const SizedBox(height: 12),
            _FeatureRow(
              icon: Icons.auto_awesome_rounded,
              label: 'Smart preference extraction',
              sub: 'Learns lead-time and reminder style from task names',
              dark: dark,
            ),
            const SizedBox(height: 8),
            _FeatureRow(
              icon: Icons.lightbulb_outline_rounded,
              label: 'Reasoning trace',
              sub: 'Plain-language explanations for every scheduling decision',
              dark: dark,
            ),
            const SizedBox(height: 8),
            _FeatureRow(
              icon: Icons.category_rounded,
              label: 'Task classification',
              sub: 'Auto-assigns categories from free-text task names',
              dark: dark,
            ),

            const SizedBox(height: 28),
            if (!_isReady && !_isLoading)
              FilledButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download model (~1 GB)'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  minimumSize: const Size.fromHeight(48),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(AppRadius.md),
                  ),
                ),
              ),
            if (_isLoading)
              FilledButton.icon(
                onPressed: null,
                icon: const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: const Text('Downloading…'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(AppRadius.md),
                  ),
                ),
              ),
            if (_isReady)
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Model ready — no action needed'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(AppRadius.md),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final bool dark;

  const _FeatureRow({
    required this.icon,
    required this.label,
    required this.sub,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final ink = dark ? AppColors.darkInk : AppColors.ink;
    final subColor = dark ? AppColors.darkInkSubtle : AppColors.inkSubtle;
    final accent = dark ? AppColors.darkDeep : AppColors.deep;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accent, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: text.bodyMedium
                      ?.copyWith(color: ink, fontWeight: FontWeight.w500)),
              Text(sub,
                  style: text.bodySmall?.copyWith(color: subColor)),
            ],
          ),
        ),
      ],
    );
  }
}
