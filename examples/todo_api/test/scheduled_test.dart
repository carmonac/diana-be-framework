import 'package:diana/diana.dart';
import 'package:test/test.dart';
import 'package:todo_api/app.diana_app.dart';

void main() {
  test('@Scheduled tasks start with initialize and stop with dispose',
      () async {
    final app = await buildDianaApp(
      config: DianaConfig({
        'app.info.name': 'test',
        'app.info.version': '0.0.0',
      }),
    );
    expect(app.context.heartbeatJob.beats, 0);

    await app.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final whileRunning = app.context.heartbeatJob.beats;
    expect(whileRunning, greaterThanOrEqualTo(2));

    await app.dispose();
    final afterDispose = app.context.heartbeatJob.beats;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(app.context.heartbeatJob.beats, afterDispose,
        reason: 'no more beats after dispose');
  });
}
