import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MiniPlayer extends StatelessWidget {
  final String trackTitle;
  final String subtitle;
  final bool isPlaying;
  final VoidCallback onTogglePlay;

  const MiniPlayer({
    super.key,
    required this.trackTitle,
    required this.subtitle,
    required this.isPlaying,
    required this.onTogglePlay,
  });

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkDeep : AppColors.deep,
        borderRadius: const BorderRadius.all(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: (dark ? AppColors.darkDeep : AppColors.deep)
                .withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Album art / icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.darkAmber.withValues(alpha: 0.25)
                  : AppColors.amber.withValues(alpha: 0.25),
              borderRadius: const BorderRadius.all(AppRadius.sm),
            ),
            child: Icon(
              Icons.music_note_rounded,
              color: dark ? AppColors.darkAmber : AppColors.amber,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 4),

          // Track info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trackTitle,
                  style: context.text.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.text.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Play / Pause
          GestureDetector(
            onTap: onTogglePlay,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
