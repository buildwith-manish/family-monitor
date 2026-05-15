import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

@pragma('vm:entry-point')
void watchdogEntrypoint() async {
  WidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.family_monitor/watchdog');

  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'onWatchdogTriggered':
        final flavor = call.arguments['flavor'] as String? ?? 'unknown';
        final timestamp = call.arguments['timestamp'] as int? ?? 0;
        await _runWatchdogCheck(flavor: flavor, timestamp: timestamp);
        return 'ok';
      default:
        throw PlatformException(
          code: 'UNKNOWN_METHOD',
          message: 'Method ${call.method} not implemented',
        );
    }
  });
}

Future<void> _runWatchdogCheck({
  required String flavor,
  required int timestamp,
}) async {
  debugPrint('[WatchdogEntrypoint] check triggered flavor=$flavor timestamp=$timestamp');
}
