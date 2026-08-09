import 'dart:async';

typedef LocationRefresh = Future<void> Function();
typedef PeriodicTimerFactory =
    Timer Function(Duration interval, void Function(Timer timer) callback);

class ForegroundLocationScheduler {
  ForegroundLocationScheduler({
    required this.refresh,
    this.interval = const Duration(seconds: 120),
    PeriodicTimerFactory? timerFactory,
  }) : _timerFactory = timerFactory ?? Timer.periodic;

  final LocationRefresh refresh;
  final Duration interval;
  final PeriodicTimerFactory _timerFactory;

  Timer? _timer;
  bool _isForeground = false;
  bool _refreshInFlight = false;

  bool get isForeground => _isForeground;

  void enterForeground({bool refreshImmediately = true}) {
    if (_isForeground) return;
    _isForeground = true;
    if (refreshImmediately) _requestRefresh();
    _timer = _timerFactory(interval, (_) => _requestRefresh());
  }

  void leaveForeground() {
    _isForeground = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => leaveForeground();

  void _requestRefresh() {
    if (!_isForeground || _refreshInFlight) return;
    _refreshInFlight = true;
    Future<void>.sync(
      refresh,
    ).catchError((_) {}).whenComplete(() => _refreshInFlight = false);
  }
}
