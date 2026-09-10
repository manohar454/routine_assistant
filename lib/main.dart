import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
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
      home: const HomeScreen(),
    );
  }
}
