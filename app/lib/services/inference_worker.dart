import 'dart:async';
import 'dart:isolate';

/// Implementations and their native handles are created only in the worker.
abstract interface class InferenceHandler {
  Object? execute(String operation, Map<String, Object?> arguments);
  void dispose();
}

typedef InferenceHandlerFactory = InferenceHandler Function();

/// A persistent isolate with a serial synchronous command loop. Native calls
/// cannot safely be interrupted: close queues destruction after outstanding work.
class InferenceWorker {
  InferenceWorker(this._factory);

  final InferenceHandlerFactory _factory;
  Future<SendPort>? _starting;
  ReceivePort? _events;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  bool _closed = false;
  Future<void>? _closing;

  Future<Object?> run(String operation, Map<String, Object?> arguments) async {
    if (_closed) throw StateError('推理工作线程已关闭');
    final port = await (_starting ??= _start());
    if (_closed) throw StateError('推理工作线程已关闭');
    return _send(port, operation, arguments);
  }

  Future<Object?> _send(
    SendPort port,
    String operation,
    Map<String, Object?> arguments,
  ) {
    final id = _nextId++;
    final result = Completer<Object?>();
    _pending[id] = result;
    try {
      port.send([id, operation, arguments]);
    } catch (error, stack) {
      _pending.remove(id);
      result.completeError(error, stack);
    }
    return result.future;
  }

  Future<SendPort> _start() async {
    final events = ReceivePort();
    _events = events;
    final ready = Completer<SendPort>();
    void fail(Object error, StackTrace stack) {
      if (!ready.isCompleted) ready.completeError(error, stack);
      for (final pending in _pending.values) {
        pending.completeError(error, stack);
      }
      _pending.clear();
      events.close();
      if (identical(_events, events)) {
        _events = null;
        _starting = null;
      }
    }

    events.listen((dynamic message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is List && message.length == 4) {
        final pending = _pending.remove(message[0]);
        if (message[1] == true) {
          pending?.complete(message[2]);
        } else {
          pending?.completeError(
            StateError(message[2] as String),
            StackTrace.fromString(message[3] as String),
          );
        }
      } else {
        fail(StateError('后台推理线程意外退出：$message'), StackTrace.current);
      }
    });
    try {
      await Isolate.spawn(
        _workerMain,
        (events.sendPort, _factory),
        onError: events.sendPort,
        onExit: events.sendPort,
        errorsAreFatal: true,
        debugName: 'ocr-tts-asr-inference',
      );
    } catch (error, stack) {
      fail(error, stack);
    }
    return ready.future;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    final starting = _starting;
    if (starting == null) return;
    try {
      final port = await starting;
      await _send(port, '__dispose', const {});
    } finally {
      _events?.close();
      _events = null;
      _starting = null;
    }
  }
}

void _workerMain((SendPort, InferenceHandlerFactory) startup) {
  final (parent, factory) = startup;
  final requests = ReceivePort();
  InferenceHandler? handler;
  parent.send(requests.sendPort);
  requests.listen((dynamic message) {
    final values = message as List;
    final id = values[0] as int;
    final operation = values[1] as String;
    try {
      if (operation == '__dispose') {
        handler?.dispose();
      } else {
        handler ??= factory();
        final result = handler!.execute(
          operation,
          (values[2] as Map).cast<String, Object?>(),
        );
        parent.send([id, true, result, null]);
        return;
      }
      parent.send([id, true, null, null]);
    } catch (error, stack) {
      parent.send([id, false, error.toString(), stack.toString()]);
    } finally {
      if (operation == '__dispose') requests.close();
    }
  });
}
