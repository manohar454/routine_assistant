import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/llm_service.dart';
import 'services/sensing_service.dart';
import 'services/routine_alarm_service.dart';
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
  runApp(const RoutineAssistantApp());
}

class RoutineAssistantApp extends StatelessWidget {
  const RoutineAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Routine Assistant',
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
