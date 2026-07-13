import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';
import 'package:test/test.dart';

/// A connector that hands back a fake, so the facade lifecycle is testable
/// without a real driver. (Full driver behaviour is exercised over sqlite in
/// database_test.dart.)
class StubConnector extends DatabaseConnector {
  final Object handle;
  bool closed = false;

  StubConnector(this.handle);

  @override
  Future<Object> connect(DianaConfig config) async => handle;

  @override
  Future<void> close(Object connection) async => closed = true;
}

void main() {
  test('open stores the connection, close delegates to the connector',
      () async {
    final connector = StubConnector(Object());
    final db = Database(connector, const DianaConfig.empty());
    await db.open();
    await db.close();
    expect(connector.closed, isTrue);
  });

  test('close is idempotent and does not double-close', () async {
    final connector = StubConnector(Object());
    final db = Database(connector, const DianaConfig.empty());
    await db.open();
    await db.close();
    connector.closed = false;
    await db.close();
    expect(connector.closed, isFalse);
  });

  test('migrate is a no-op without db.migrations.dir', () async {
    final db = Database(StubConnector(Object()), const DianaConfig.empty());
    await db.open();
    await db.migrate(); // must not touch the connection
    await db.close();
  });
}
