import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/llm_service.dart';
import 'services/sensing_service.dart';
import 'services/routine_alarm_service.dart';
import 'engine/day_clustering_engine.dart';
import 'db/database_helper.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  // Register the LiteRT inference engine — does NOT download the model yet.
  // Model downloads lazily on first use (from settings or first task save).
  await LlmService.initialize();
  // Start passive accelerometer listening for motion-level signal.
  await SensingService.instance.init();
  // Schedule today's routine alarms (no-op if user hasn't set them up yet).
  await RoutineAlarmService.instance.scheduleAll();
  // Phase 3: weekly cluster retrain — runs silently in background.
  _maybeRetrainClusters();
  runApp(const RoutineAssistantApp());
}

/// Runs cluster retraining at most once per week.
/// Checks the last retrain timestamp stored in app_settings.
Future<void> _maybeRetrainClusters() async {
  try {
    final db = DatabaseHelper.instance;
    final lastStr = await db.getSetting('last_cluster_retrain');
    if (lastStr != null) {
      final last = DateTime.tryParse(lastStr);
      if (last != null &&
          DateTime.now().difference(last).inDays < 7) {
        return; // retrained within the last 7 days — skip
      }
    }
    await DayClusteringEngine.instance.retrainClusters();
    await db.setSetting(
        'last_cluster_retrain', DateTime.now().toIso8601String());
  } catch (_) {
    // Non-critical — retrain will retry on next launch.
  }
}

class RoutineAssistantApp extends StatelessWidget {
  const RoutineAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rhythmiq',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system, // follows device dark/light setting
      // Global navigator key so notification taps can push routes.
      navigatorKey: routineNavigatorKey,
      home: const HomeScreen(),
    );
  }
}
