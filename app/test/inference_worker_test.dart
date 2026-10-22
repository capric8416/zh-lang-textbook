import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/services/inference_worker.dart';

InferenceHandler createTestHandler() => TestHandler();

class TestHandler implements InferenceHandler {
  int count = 0;
  SendPort? lifecycle;
  @override
  Object? execute(String operation, Map<String, Object?> arguments) {
    switch (operation) {
      case 'block':
        (arguments['started'] as SendPort).send(true);
        sleep(const Duration(milliseconds: 200));
        return ++count;
      case 'count':
        return ++count;
      case 'fail':
        throw StateError('model failed');
      case 'exit':
        Isolate.exit();
      case 'bytes':
        return (arguments['pixels'] as TransferableTypedData)
            .materialize()
            .asUint8List()
            .toList();
      case 'lifecycle':
        lifecycle = arguments['port'] as SendPort;
        return null;
      default:
        throw ArgumentError(operation);
    }
  }

  @override
  void dispose() => lifecycle?.send('disposed');
}

void main() {
  test(
    'blocking inference leaves caller responsive and preserves FIFO state',
    () async {
      final worker = InferenceWorker(createTestHandler);
      addTearDown(worker.close);
      final started = ReceivePort();
      addTearDown(started.close);
      var finished = false;
      final first = worker.run('block', {'started': started.sendPort}).then((
        value,
      ) {
        finished = true;
        return value;
      });
      await started.first;
      final second = worker.run('count', {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(finished, false);
      expect(await first, 1);
      expect(await second, 2);
    },
  );

  test('transfers pixels and recovers from a failed command', () async {
    final worker = InferenceWorker(createTestHandler);
    addTearDown(worker.close);
    await expectLater(worker.run('fail', {}), throwsStateError);
    expect(
      await worker.run('bytes', {
        'pixels': TransferableTypedData.fromList([
          Uint8List.fromList([0, 128, 255]),
        ]),
      }),
      [0, 128, 255],
    );
    expect(await worker.run('count', {}), 1);
  });

  test(
    'shutdown drains work and disposes on worker before rejecting new work',
    () async {
      final worker = InferenceWorker(createTestHandler);
      final lifecycle = ReceivePort();
      final started = ReceivePort();
      addTearDown(lifecycle.close);
      addTearDown(started.close);
      await worker.run('lifecycle', {'port': lifecycle.sendPort});
      final task = worker.run('block', {'started': started.sendPort});
      await started.first;
      final close = worker.close();
      await expectLater(worker.run('count', {}), throwsStateError);
      expect(await task, 1);
      expect(await lifecycle.first, 'disposed');
      await close;
      await worker.close();
    },
  );

  test(
    'unexpected isolate exit completes request and allows restart',
    () async {
      final worker = InferenceWorker(createTestHandler);
      addTearDown(worker.close);
      await expectLater(worker.run('exit', {}), throwsStateError);
      expect(await worker.run('count', {}), 1);
    },
  );
}
