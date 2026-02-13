import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:awesome_notifications/awesome_notifications.dart';

import 'package:doable_todo_list_app/services/notification_service.dart';
import 'package:doable_todo_list_app/repositories/task_repository.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _prefsKeyNotifications = 'notifications_enabled';

  bool _notificationsEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefsKeyNotifications) ?? false;
    setState(() {
      _notificationsEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _setNotifications(bool value) async {
    // Ask permission when enabling; if denied, keep it disabled.
    if (value) {
      final granted = await _requestNotificationPermission();
      if (!mounted) return;
      if (!granted) {
        // Inform user and keep toggle off
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification permission denied')),
        );
        value = false;
      } else {

        try {
          final tasks = await TaskRepository().fetchAll();
          await NotificationService.rescheduleAllNotifications(tasks);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notifications enabled and scheduled')),
          );
        } catch (e) {
          print('Error rescheduling notifications: $e');
        }
      }
    } else {
      // When disabling notifications, cancel all scheduled notifications
      try {
        await NotificationService.cancelAllNotifications();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications cancelled')),
        );
      } catch (e) {
        print('Error cancelling notifications: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyNotifications, value);
    if (!mounted) return;
    setState(() => _notificationsEnabled = value);
  }

  // Request notification permission using awesome_notifications
  Future<bool> _requestNotificationPermission() async {
    return await NotificationService.requestPermissions();
  }

  Future<void> _sendTestNotification() async {
    // Check both system permission and user preference
    final isAllowed = await NotificationService.isNotificationAllowed();
    if (!isAllowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification permission required')),
      );
      return;
    }

    if (!_notificationsEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications are disabled in settings')),
      );
      return;
    }

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: 999999, // Use a high ID for test notifications
        channelKey: NotificationService.channelKey,
        title: 'Test Notification',
        body: 'This is a test notification to verify notifications are working!',
        category: NotificationCategory.Reminder,
        payload: {'test': 'true'},
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test notification sent')),
    );
  }

  Future<void> _confirmAndClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text('This will delete all tasks and reset the app to a fresh state. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Wipe the tasks table
    await TaskRepository().clearAll();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All data cleared')),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  EdgeInsets get _screenHPad {
    final w = MediaQuery.of(context).size.width;
    final hpad = (w * 0.05).clamp(16.0, 24.0);
    return EdgeInsets.symmetric(horizontal: hpad);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final version = '1.0.0';
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black),
          tooltip: 'Back',
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
          padding: _screenHPad.add(const EdgeInsets.only(bottom: 24, top: 8)),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(fontSize: 16, color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w600),
                ),
                Switch(
                  value: _notificationsEnabled,
                  onChanged: _setNotifications,
                  activeThumbColor: colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Dark Mode',
                  style: TextStyle(fontSize: 16, color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w600),
                ),
                ValueListenableBuilder<AdaptiveThemeMode>(
                  valueListenable: AdaptiveTheme.of(context).modeChangeNotifier,
                  builder: (_, mode, __) {
                    return SegmentedButton<AdaptiveThemeMode>(
                      segments: [
                        ButtonSegment(
                          value: AdaptiveThemeMode.light,
                          icon: Icon(Icons.light_mode, size: 18, color: isDark ? Colors.white : Colors.black),
                        ),
                        ButtonSegment(
                          value: AdaptiveThemeMode.system,
                          icon: Icon(Icons.brightness_auto, size: 18, color: isDark ? Colors.white : Colors.black),
                        ),
                        ButtonSegment(
                          value: AdaptiveThemeMode.dark,
                          icon: Icon(Icons.dark_mode, size: 18, color: isDark ? Colors.white : Colors.black),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (selection) {
                        AdaptiveTheme.of(context).setThemeMode(selection.first);
                      },
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: isDark ? colorScheme.primary : Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                onPressed: _confirmAndClearAll,
                child: const Text('Clear All Data'),
              ),
            ),

            const SizedBox(height: 24),
            Divider(height: 1, color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE5E7EB)),

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'License',
                    style: TextStyle(fontSize: 14, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontWeight: FontWeight.w600),
                  ),
                ),
                Text('MIT', style: TextStyle(fontSize: 14, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Version',
                    style: TextStyle(fontSize: 14, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(version, style: TextStyle(fontSize: 14, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontWeight: FontWeight.w700)),
              ],
            ),

            SizedBox(height: MediaQuery.of(context).size.height * 0.12),

            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset('assets/trans_logo.svg', height: 56, colorFilter: ColorFilter.mode(isDark ? Colors.white : Colors.black, BlendMode.srcIn)),
                const SizedBox(height: 8),
                Text(
                  'Version $version',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 32),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SocialIconButton(
                      asset: 'assets/twitter.svg',
                      tooltip: 'X',
                      onTap: () => _openUrl('https://x.com/AkhinAbr'),
                    ),
                    const SizedBox(width: 16),
                    _SocialIconButton(
                      asset: 'assets/github.svg',
                      tooltip: 'GitHub',
                      onTap: () => _openUrl('https://github.com/theakhinabraham'),
                    ),
                    const SizedBox(width: 16),
                    _SocialIconButton(
                      asset: 'assets/linkedin.svg',
                      tooltip: 'LinkedIn',
                      onTap: () => _openUrl('https://www.linkedin.com/in/theakhinabraham'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialIconButton extends StatelessWidget {
  const _SocialIconButton({
    required this.asset,
    required this.onTap,
    required this.tooltip,
  });

  final String asset;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return InkResponse(
      onTap: onTap,
      radius: 28,
      customBorder: const CircleBorder(),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.04),
        ),
        alignment: Alignment.center,
        child: Tooltip(
          message: tooltip,
          child: SvgPicture.asset(
            asset,
            height: 32,
            width: 32,
            colorFilter: ColorFilter.mode(isDark ? Colors.white : Colors.black, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}