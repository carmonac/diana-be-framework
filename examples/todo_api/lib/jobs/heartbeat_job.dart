import 'package:diana/diana.dart';

/// Demonstrates @Scheduled: a fixed-delay heartbeat and a cron task, both
/// keeping counters observable in tests.
@Component()
class HeartbeatJob {
  int beats = 0;
  int cronTicks = 0;

  @Scheduled(fixedDelay: 50)
  void beat() => beats++;

  /// The fastest cron cadence — once per second.
  @Scheduled(cron: '* * * * * *')
  Future<void> everySecond() async => cronTicks++;
}
