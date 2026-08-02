class ChatTimePresentation {
  const ChatTimePresentation._();

  static const dividerInterval = Duration(minutes: 5);

  static bool shouldShowDivider(DateTime current, DateTime? previous) {
    if (previous == null) return true;
    if (!_sameDay(current, previous)) return true;
    return current.difference(previous).abs() >= dividerInterval;
  }

  static String format(DateTime value, {DateTime? now}) {
    final local = value.toLocal();
    final reference = (now ?? DateTime.now()).toLocal();
    final time = '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
    if (_sameDay(local, reference)) return time;

    final yesterday = DateTime(
      reference.year,
      reference.month,
      reference.day,
    ).subtract(const Duration(days: 1));
    if (_sameDay(local, yesterday)) return '昨天 $time';
    if (local.year == reference.year) {
      return '${local.month}月${local.day}日 $time';
    }
    return '${local.year}年${local.month}月${local.day}日 $time';
  }

  static bool _sameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
