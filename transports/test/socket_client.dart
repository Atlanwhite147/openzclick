/// Test helpers: socket client and typed event log.
///
/// Contains no test on purpose: it is imported by the `*_test.dart` files.
library;

import 'dart:async';
import 'dart:io';

/// Minimal TCP client that buffers what it receives.
///
/// A [Socket] is a single-subscription stream, so it is listened to exactly once
/// at construction and bytes are queued: tests can then wait for a precise
/// number of bytes, in order, without racing the event loop.
class SocketClient {
  /// Starts listening on [socket].
  SocketClient(Socket socket) : _socket = socket {
    _subscription = socket.listen(
      _onData,
      onError: (Object error) {
        _error = error;
        _completeDone();
      },
      onDone: _completeDone,
      cancelOnError: false,
    );
  }

  /// Connects to `127.0.0.1:[port]` and returns a buffered client.
  static Future<SocketClient> connect(int port) async {
    final Socket socket =
        await Socket.connect(InternetAddress.loopbackIPv4, port);
    return SocketClient(socket);
  }

  final Socket _socket;
  late final StreamSubscription<List<int>> _subscription;
  final List<int> _buffer = <int>[];
  final List<int> _received = <int>[];
  final Completer<void> _done = Completer<void>();
  Completer<void>? _waiter;
  Object? _error;

  /// Every byte received since connection, never consumed.
  List<int> get received => List<int>.unmodifiable(_received);

  /// True once the socket is closed or failed.
  bool get isClosed => _done.isCompleted;

  /// Error raised by the socket, if any.
  Object? get error => _error;

  /// Completes when the socket closes.
  Future<void> get done => _done.future;

  /// Writes [bytes] and flushes them.
  Future<void> send(List<int> bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  /// Waits for [count] bytes and returns them, consuming them from the queue.
  Future<List<int>> take(
    int count, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final Stopwatch watch = Stopwatch()..start();
    while (_buffer.length < count) {
      if (isClosed) {
        throw StateError(
          'socket closed after ${_buffer.length} buffered byte(s), '
          '$count expected (received: $_received)',
        );
      }
      final Duration remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException(
          '$count byte(s) expected, ${_buffer.length} available '
          '(received: $_received)',
          timeout,
        );
      }
      final Completer<void> waiter = Completer<void>();
      _waiter = waiter;
      await waiter.future.timeout(remaining, onTimeout: () {});
      if (identical(_waiter, waiter)) {
        _waiter = null;
      }
    }
    final List<int> out = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return out;
  }

  /// Closes the client and releases its subscription.
  Future<void> close() async {
    await _subscription.cancel();
    _socket.destroy();
    _completeDone();
  }

  void _onData(List<int> chunk) {
    _received.addAll(chunk);
    _buffer.addAll(chunk);
    final Completer<void>? waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }

  void _completeDone() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}

/// Records every event of a stream and lets tests await the next one of a type.
class EventLog<T extends Object> {
  /// Subscribes to [stream] immediately.
  EventLog(Stream<T> stream) {
    _subscription = stream.listen(_events.add);
  }

  final List<T> _events = <T>[];
  late final StreamSubscription<T> _subscription;
  int _cursor = 0;

  /// Every event recorded so far, in order.
  List<T> get events => List<T>.unmodifiable(_events);

  /// Waits for the next event of type [E] after the previous match.
  ///
  /// Events of other types seen before it are skipped, so a test can ignore
  /// interleaved traffic. Throws [TimeoutException] with the full log when
  /// nothing matches in time.
  Future<E> next<E extends T>({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final Stopwatch watch = Stopwatch()..start();
    while (true) {
      while (_cursor < _events.length) {
        final T event = _events[_cursor++];
        if (event is E) {
          return event;
        }
      }
      if (watch.elapsed > timeout) {
        throw TimeoutException(
            'no event of type $E within $timeout (log: $_events)');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Waits [within] and fails if an event of type [E] shows up.
  Future<void> expectNone<E extends T>({
    Duration within = const Duration(milliseconds: 150),
  }) async {
    await Future<void>.delayed(within);
    final Iterable<E> matches = _events.whereType<E>();
    if (matches.isNotEmpty) {
      throw StateError('unexpected event(s): $matches');
    }
  }

  /// Releases the subscription.
  Future<void> cancel() => _subscription.cancel();
}
