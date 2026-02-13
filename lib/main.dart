import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:doable_todo_list_app/services/notification_service.dart';
import 'package:doable_todo_list_app/repositories/task_repository.dart';
import 'package:doable_todo_list_app/data/database_service.dart';
import 'package:doable_todo_list_app/screens/add_task_page.dart';
import 'package:doable_todo_list_app/screens/chat_page.dart';
import 'package:doable_todo_list_app/screens/ai_settings_page.dart';
import 'package:doable_todo_list_app/screens/model_picker_page.dart';
import 'package:doable_todo_list_app/screens/edit_task_page.dart';
import 'package:doable_todo_list_app/screens/home_page.dart';
import 'package:doable_todo_list_app/screens/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _seedColor = Color(0xFF3B82F6);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database - use FFI for desktop, default for mobile
  await DatabaseService.initialize();

  await AwesomeNotifications().initialize(
    null,
    [
      NotificationChannel(
        channelKey: 'task_reminders',
        channelName: 'Task Reminders',
        channelDescription: 'Notifications for task reminders',
        defaultColor: _seedColor,
        ledColor: _seedColor,
        importance: NotificationImportance.High,
        channelShowBadge: true,
        playSound: true,
        enableVibration: true,
      ),
    ],
  );

  await NotificationService.requestPermissions();

  try {
    final tasks = await TaskRepository().fetchAll();
    await NotificationService.rescheduleAllNotifications(tasks);
  } catch (_) {}

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  runApp(const DoableApp());
}

class DoableApp extends StatefulWidget {
  const DoableApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<DoableApp> createState() => _DoableAppState();
}

class _DoableAppState extends State<DoableApp> {
  @override
  void initState() {
    super.initState();
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: onActionReceivedMethod,
      onNotificationCreatedMethod: onNotificationCreatedMethod,
      onNotificationDisplayedMethod: onNotificationDisplayedMethod,
      onDismissActionReceivedMethod: onDismissActionReceivedMethod,
    );
  }

  @pragma("vm:entry-point")
  static Future<void> onActionReceivedMethod(ReceivedAction receivedAction) async {
    if (receivedAction.payload?['task_id'] != null) {
      DoableApp.navigatorKey.currentState?.pushNamedAndRemoveUntil('home', (route) => false);
    }
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationCreatedMethod(ReceivedNotification receivedNotification) async {}

  @pragma("vm:entry-point")
  static Future<void> onNotificationDisplayedMethod(ReceivedNotification receivedNotification) async {}

  @pragma("vm:entry-point")
  static Future<void> onDismissActionReceivedMethod(ReceivedAction receivedAction) async {}

  @override
  Widget build(BuildContext context) {
    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF3F4F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: _seedColor, width: 2),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE5E7EB),
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: Color(0xFF374151)),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Color(0xFF111827)),
        bodyMedium: TextStyle(color: Color(0xFF374151)),
        bodySmall: TextStyle(color: Color(0xFF6B7280)),
        titleLarge: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w800),
        titleMedium: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: Color(0xFF374151), fontWeight: FontWeight.w600),
        labelLarge: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: Color(0xFF374151)),
        labelSmall: TextStyle(color: Color(0xFF6B7280)),
      ),
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F0F0F),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Color(0xFF1A1A1A),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1A1A1A),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2D2D2D)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF262626),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: _seedColor, width: 2),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _seedColor,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2D2D2D),
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: Color(0xFFD1D5DB)),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Color(0xFFF9FAFB)),
        bodyMedium: TextStyle(color: Color(0xFFD1D5DB)),
        bodySmall: TextStyle(color: Color(0xFF9CA3AF)),
        titleLarge: TextStyle(color: Color(0xFFF9FAFB), fontWeight: FontWeight.w800),
        titleMedium: TextStyle(color: Color(0xFFF9FAFB), fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: Color(0xFFD1D5DB), fontWeight: FontWeight.w600),
        labelLarge: TextStyle(color: Color(0xFFF9FAFB), fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: Color(0xFFD1D5DB)),
        labelSmall: TextStyle(color: Color(0xFF9CA3AF)),
      ),
    );

    return AdaptiveTheme(
      light: lightTheme,
      dark: darkTheme,
      initial: AdaptiveThemeMode.system,
      builder: (theme, darkTheme) => MaterialApp(
        navigatorKey: DoableApp.navigatorKey,
        title: 'Doable',
        debugShowCheckedModeBanner: false,
        theme: theme,
        darkTheme: darkTheme,
        initialRoute: 'home',
        routes: {
          'home': (context) => const HomePage(),
          'add_task': (context) => const AddTaskPage(),
          'edit_task': (context) => const EditTaskPage(),
          'settings': (context) => const SettingsPage(),
          'chat': (context) => const ChatPage(),
          'ai_settings': (context) => const AISettingsPage(),
          'model_picker': (context) => const ModelPickerPage(),
        },
      ),
    );
  }
}
