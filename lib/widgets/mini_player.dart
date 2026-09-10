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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.deep,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.amber,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.music_note, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trackTitle,
                  style: const TextStyle(
                    color: AppColors.canvas,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFFA9BCC4), fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onTogglePlay,
            icon: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: AppColors.canvas,
            ),
          ),
        ],
      ),
    );
  }
}
