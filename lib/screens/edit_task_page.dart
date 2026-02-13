import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import 'package:doable_todo_list_app/models/task_entity.dart';
import 'package:doable_todo_list_app/repositories/task_repository.dart';
import 'package:doable_todo_list_app/services/notification_service.dart';

// Import Task view model from Home if you keep it there,
// or duplicate the minimal fields you need here.
import 'package:doable_todo_list_app/screens/home_page.dart' show Task;

class EditTaskPage extends StatefulWidget {
  const EditTaskPage({super.key});

  @override
  State<EditTaskPage> createState() => _EditTaskPageState();
}

class _EditTaskPageState extends State<EditTaskPage> {
  // Controllers
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // Incoming task to edit
  late Task _task;

  // UI state
  bool _reminder = false;
  String? _repeatRule; // "Daily" | "Weekly" | "Monthly" | "No repeat" | null
  final Set<int> _repeatWeekdays = {}; // 1=Mon ... 7=Sun
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  // Style constants
  static const Color blueColor = Color(0xFF2563EB); // button/active color

  // Convenience paddings
  EdgeInsets get _screenHPad {
    final w = MediaQuery.of(context).size.width;
    final hpad = (w * 0.05).clamp(16.0, 24.0);
    return EdgeInsets.symmetric(horizontal: hpad);
  }

  @override
  void initState() {
    super.initState();
    // Read arguments after first frame to ensure context is mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final arg = ModalRoute.of(context)!.settings.arguments;
      _task = arg as Task;

      // Prefill text
      _titleCtrl.text = _task.title;
      _descCtrl.text = _task.description ?? '';

      // Prefill toggles
      _reminder = _task.hasNotification;
      _repeatRule = _task.repeatRule;
      _hydrateWeekdaysFromRule(_repeatRule);

      // Prefill date/time (parse stored display strings)
      _selectedDate = _parseDateOrNull(_task.date);
      _selectedTime = _parseTimeOrNull(_task.time);

      setState(() {});
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ===== Formatting / parsing =====

  String _formatDate(DateTime d) => DateFormat('dd/MM/yy').format(d);

  String _formatTime(TimeOfDay t) {
    final dt = DateTime(0, 1, 1, t.hour, t.minute);
    return DateFormat('h:mm a').format(dt);
  }

  DateTime? _parseDateOrNull(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      return DateFormat('dd/MM/yy').parseStrict(s);
    } catch (_) {
      return null;
    }
  }

  TimeOfDay? _parseTimeOrNull(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      final dt = DateFormat('h:mm a').parseStrict(s);
      return TimeOfDay.fromDateTime(dt);
    } catch (_) {
      return null;
    }
  }

  // ===== Repeat helpers (Weekly day parsing/selection) =====

  void _hydrateWeekdaysFromRule(String? rule) {
    _repeatWeekdays.clear();
    if (rule == null) return;
    if (!rule.startsWith('Weekly')) return;

    // Supports "Weekly:[1,2,3]" or "Weekly:1,2,3" or variants with spaces
    final exp = RegExp(r'(\d+)');
    for (final m in exp.allMatches(rule)) {
      final v = int.tryParse(m.group(1)!);
      if (v != null && v >= 1 && v <= 7) _repeatWeekdays.add(v);
    }
  }

  void _selectRepeatRule(String rule) {
    setState(() {
      _repeatRule = rule;
      if (rule != 'Weekly') {
        _repeatWeekdays.clear();
      }
    });
  }

  void _toggleWeekday(int weekday) {
    setState(() {
      if (_repeatWeekdays.contains(weekday)) {
        _repeatWeekdays.remove(weekday);
      } else {
        _repeatWeekdays.add(weekday);
      }
      if (_repeatWeekdays.isNotEmpty) {
        _repeatRule = 'Weekly'; // force Weekly if any day is picked
      }
    });
  }

  // ===== Pickers =====

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Select date',
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      helpText: 'Select time',
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  void _toggleReminder() async {
    final userEnabled = await NotificationService.areNotificationsEnabledByUser();

    if (!userEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Notifications are disabled in settings'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () {
              Navigator.pushNamed(context, 'settings');
            },
          ),
        ),
      );
      return;
    }

    setState(() => _reminder = !_reminder);
  }

  // ===== Save =====

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }

    // Build display strings
    final dateStr = _selectedDate != null ? _formatDate(_selectedDate!) : null;
    final timeStr = _selectedTime != null ? _formatTime(_selectedTime!) : null;

    // Build repeat rule string
    String? normalizedRepeat;
    if (_repeatRule == null || _repeatRule == 'No repeat') {
      normalizedRepeat = null;
    } else if (_repeatRule == 'Weekly' && _repeatWeekdays.isNotEmpty) {
      final list = _repeatWeekdays.toList()..sort(); // 1..7 stable order
      normalizedRepeat = 'Weekly:${list.toString()}'; // Weekly:[1,2,4]
    } else {
      normalizedRepeat = _repeatRule;
    }

    final entity = TaskEntity(
      id: _task.id, // required for update
      title: title,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      time: timeStr,
      date: dateStr,
      hasNotification: _reminder,
      repeatRule: normalizedRepeat,
      completed: _task.completed, // preserve current completed state
    );

    await TaskRepository().update(entity);

    if (mounted) Navigator.pop(context, true); // signal Home to refresh
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    if (!(_titleCtrl.text.isNotEmpty || ModalRoute.of(context)?.settings.arguments != null)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final spacing = 16.0;
    final bigSpacing = 24.0;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.pop(context, false),
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black),
          tooltip: 'Back',
        ),
        title: Text(
          'Modify to-do',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: _screenHPad.add(const EdgeInsets.only(bottom: 24, top: 8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReminderButton(
                enabled: _reminder,
                onTap: _toggleReminder,
              ),
              SizedBox(height: bigSpacing),

              _FieldLabel(text: 'Tell us about your task'),
              SizedBox(height: spacing),

              _InputField(
                controller: _titleCtrl,
                hint: 'Title',
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: spacing),
              _InputField(
                controller: _descCtrl,
                hint: 'Description',
                maxLines: 3,
              ),
              SizedBox(height: bigSpacing),

              _FieldLabel(text: 'Repeat'),
              SizedBox(height: spacing),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _RepeatChip(
                    label: 'Daily',
                    selected: _repeatRule == 'Daily',
                    onTap: () => _selectRepeatRule('Daily'),
                  ),
                  _RepeatChip(
                    label: 'Weekly',
                    selected: _repeatRule == 'Weekly',
                    onTap: () => _selectRepeatRule('Weekly'),
                  ),
                  _RepeatChip(
                    label: 'Monthly',
                    selected: _repeatRule == 'Monthly',
                    onTap: () => _selectRepeatRule('Monthly'),
                  ),
                  _RepeatChip(
                    label: 'No repeat',
                    selected: _repeatRule == null || _repeatRule == 'No repeat',
                    onTap: () => _selectRepeatRule('No repeat'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _WeekdayChip(
                    label: 'Sunday',
                    selected: _repeatWeekdays.contains(7),
                    onTap: () => _toggleWeekday(7),
                  ),
                  _WeekdayChip(
                    label: 'Monday',
                    selected: _repeatWeekdays.contains(1),
                    onTap: () => _toggleWeekday(1),
                  ),
                  _WeekdayChip(
                    label: 'Tuesday',
                    selected: _repeatWeekdays.contains(2),
                    onTap: () => _toggleWeekday(2),
                  ),
                  _WeekdayChip(
                    label: 'Wednesday',
                    selected: _repeatWeekdays.contains(3),
                    onTap: () => _toggleWeekday(3),
                  ),
                  _WeekdayChip(
                    label: 'Thursday',
                    selected: _repeatWeekdays.contains(4),
                    onTap: () => _toggleWeekday(4),
                  ),
                  _WeekdayChip(
                    label: 'Friday',
                    selected: _repeatWeekdays.contains(5),
                    onTap: () => _toggleWeekday(5),
                  ),
                  _WeekdayChip(
                    label: 'Saturday',
                    selected: _repeatWeekdays.contains(6),
                    onTap: () => _toggleWeekday(6),
                  ),
                ],
              ),
              SizedBox(height: bigSpacing),

              _FieldLabel(text: 'Date & Time'),
              SizedBox(height: spacing),

              _PickerField(
                hint: 'Set date',
                valueText: _selectedDate != null ? _formatDate(_selectedDate!) : null,
                iconAsset: 'assets/calendar.svg',
                onTap: _pickDate,
                onClear: _selectedDate != null
                    ? () => setState(() => _selectedDate = null)
                    : null,
              ),
              SizedBox(height: spacing),

              _PickerField(
                hint: 'Set time',
                valueText: _selectedTime != null ? _formatTime(_selectedTime!) : null,
                iconAsset: 'assets/clock.svg',
                onTap: _pickTime,
                onClear: _selectedTime != null
                    ? () => setState(() => _selectedTime = null)
                    : null,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),
        ),
      ),
    );
  }
}

/* ================= Reusable widgets ================= */

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});
  final String text;
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Text(
      text,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return TextField(
      controller: controller,
      textInputAction: textInputAction,
      maxLines: maxLines,
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.black45),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        filled: true,
        fillColor: isDark ? const Color(0xFF262626) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: isDark ? const Color(0xFF404040) : Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: isDark ? const Color(0xFF404040) : Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
        ),
      ),
    );
  }
}

class _ReminderButton extends StatelessWidget {
  const _ReminderButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = enabled ? const Color(0xFF3B82F6) : (isDark ? const Color(0xFF262626) : Colors.white);
    final fg = enabled ? Colors.white : (isDark ? Colors.white : Colors.black);

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: bg,
        shape: StadiumBorder(
          side: BorderSide(color: isDark ? const Color(0xFF404040) : Colors.grey.shade300),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Set Reminder',
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                SvgPicture.asset(
                  enabled ? 'assets/bell_white.svg' : 'assets/bell.svg',
                  height: 18,
                  width: 18,
                  colorFilter: enabled
                      ? null
                      : ColorFilter.mode(isDark ? Colors.white : Colors.black87, BlendMode.srcIn),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RepeatChip extends StatelessWidget {
  const _RepeatChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = selected ? (isDark ? const Color(0xFF3B82F6) : Colors.black) : (isDark ? const Color(0xFF262626) : Colors.white);
    final fg = selected ? Colors.white : (isDark ? Colors.white : Colors.black);

    return Material(
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: isDark ? const Color(0xFF404040) : Colors.grey.shade300)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekdayChip extends StatelessWidget {
  const _WeekdayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = selected ? (isDark ? const Color(0xFF3B82F6) : Colors.black) : (isDark ? const Color(0xFF262626) : Colors.white);
    final fg = selected ? Colors.white : (isDark ? Colors.white : Colors.black);

    return Material(
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: isDark ? const Color(0xFF404040) : Colors.grey.shade300)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.hint,
    required this.iconAsset,
    required this.onTap,
    this.valueText,
    this.onClear,
  });

  final String hint;
  final String iconAsset;
  final String? valueText;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasValue = valueText != null && valueText!.isNotEmpty;

    return Material(
      color: isDark ? const Color(0xFF262626) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? const Color(0xFF404040) : Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              SvgPicture.asset(
                iconAsset,
                height: 18,
                width: 18,
                colorFilter:
                ColorFilter.mode(isDark ? Colors.white : Colors.black87, BlendMode.srcIn),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasValue ? valueText! : hint,
                  style: TextStyle(
                    color: hasValue ? (isDark ? Colors.white : Colors.black) : (isDark ? Colors.grey.shade500 : Colors.black54),
                    fontWeight: hasValue ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              if (hasValue && onClear != null)
                IconButton(
                  tooltip: 'Clear',
                  icon: Icon(Icons.close, size: 20, color: isDark ? Colors.grey.shade500 : Colors.black54),
                  onPressed: onClear,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
