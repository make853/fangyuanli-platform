import 'dart:async';

import 'package:fangyuanli_mobile/src/core/location/foreground_location_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('前台立即刷新并按120秒调度，后台停止且不重叠请求', () async {
    var refreshCount = 0;
    var activeRefresh = Completer<void>();
    late _FakeTimer timer;
    final scheduler = ForegroundLocationScheduler(
      refresh: () {
        refreshCount += 1;
        return activeRefresh.future;
      },
      timerFactory: (interval, callback) {
        expect(interval, const Duration(seconds: 120));
        timer = _FakeTimer(callback);
        return timer;
      },
    );

    scheduler.enterForeground();
    expect(refreshCount, 1);
    timer.fire();
    expect(refreshCount, 1);

    activeRefresh.complete();
    await Future<void>.delayed(Duration.zero);
    activeRefresh = Completer<void>();
    timer.fire();
    expect(refreshCount, 2);

    scheduler.leaveForeground();
    activeRefresh.complete();
    await Future<void>.delayed(Duration.zero);
    timer.fire();
    expect(refreshCount, 2);
    expect(timer.isActive, isFalse);

    activeRefresh = Completer<void>();
    scheduler.enterForeground();
    expect(refreshCount, 3);
    expect(timer.isActive, isTrue);

    scheduler.dispose();
    expect(timer.isActive, isFalse);
    activeRefresh.complete();
  });
}

class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function(Timer timer) _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _tick += 1;
    _callback(this);
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}
