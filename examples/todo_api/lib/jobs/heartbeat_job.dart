import 'package:diana/diana.dart';

/// Demonstrates @Scheduled: runs after startup on a fixed delay and keeps a
/// counter observable in tests.
@Component()
class HeartbeatJob {
  int beats = 0;

  @Scheduled(fixedDelay: 50)
  void beat() => beats++;
}
