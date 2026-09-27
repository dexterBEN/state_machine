import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/wash_state.dart';
import 'washer_repository.dart';

final class WebSocketWasherRepository implements WasherRepository {
  final String wsUrl;
  final _updates = StreamController<WasherUpdate>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  Future<void>? _connectFuture;
  Future<void>? _disconnectFuture;
  Future<void>? _closeFuture;
  bool _connected = false;
  bool _isClosing = false;

  WebSocketWasherRepository({required this.wsUrl});

  @override
  Stream<WasherUpdate> get updates => _updates.stream;

  void _publish(WasherUpdate update) {
    if (!_isClosing) _updates.add(update);
  }

  @override
  Future<void> connect() {
    if (_isClosing || _disconnectFuture != null) return Future<void>.value();
    if (_channel != null) return _connectFuture ?? Future<void>.value();
    return _connectFuture ??=
        _connect().whenComplete(() => _connectFuture = null);
  }

  Future<void> _connect() async {
    WebSocketChannel? connectingChannel;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      connectingChannel = channel;
      _channel = channel;
      bool isActive() => !_isClosing && identical(_channel, channel);

      _channelSubscription = channel.stream.listen(
        (message) {
          if (!isActive()) return;
          try {
            final state = _decodeState(message);
            if (state != null) _publish(WasherStateReceived(state));
          } on FormatException catch (error) {
            _publish(WasherFailure(error.message));
          }
        },
        onError: (Object error) {
          if (isActive()) unawaited(_connectionLost(error));
        },
        onDone: () {
          if (isActive()) unawaited(_connectionLost());
        },
      );

      await channel.ready;
      if (isActive()) {
        _connected = true;
        _publish(const WasherConnectionChanged(true));
      }
    } catch (error) {
      if (_isClosing ||
          (connectingChannel != null &&
              !identical(_channel, connectingChannel))) {
        return;
      }
      await _connectionLost(error);
    }
  }

  Future<void> _connectionLost([Object? error]) async {
    _connected = false;
    String? message = error?.toString();
    try {
      await _disposeChannel();
    } catch (cleanupError) {
      message ??= cleanupError.toString();
    }
    _publish(WasherConnectionChanged(false, error: message));
  }

  // Supported wire formats: WASH or {"type":"state","value":"WASH"}.
  // Other JSON message types are ignored; invalid states never become IDLE.
  WashState? _decodeState(Object? message) {
    if (message is! String) {
      throw const FormatException('Expected a text WebSocket message.');
    }
    final raw = message.trim();
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return _parseState(raw);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected a state message object.');
    }
    if (decoded['type'] != 'state') return null;
    final value = decoded['value'];
    if (value is! String) {
      throw const FormatException('State value must be a string.');
    }
    return _parseState(value);
  }

  WashState _parseState(String value) {
    final normalized = value.trim().toLowerCase();
    return WashState.values.firstWhere(
      (state) => state.name == normalized,
      orElse: () => throw FormatException('Unknown wash state: $value'),
    );
  }

  @override
  void start() => _send('START');

  @override
  void reset() => _send('RESET');

  void _send(String command) {
    if (_isClosing || !_connected) return;
    try {
      _channel?.sink.add(command);
    } catch (error) {
      _publish(WasherFailure(error.toString()));
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _disposeChannel();
      _publish(const WasherConnectionChanged(false));
    } catch (error) {
      _publish(WasherConnectionChanged(false, error: error.toString()));
    }
  }

  Future<void> _disposeChannel() => _disconnectFuture ??=
      _releaseChannel().whenComplete(() => _disconnectFuture = null);

  Future<void> _releaseChannel() async {
    final subscription = _channelSubscription;
    final channel = _channel;
    _connected = false;
    // Invalidate callbacks synchronously, including those of an old connection.
    _channelSubscription = null;
    _channel = null;
    try {
      await subscription?.cancel();
    } finally {
      await channel?.sink.close();
    }
  }

  @override
  Future<void> close() {
    _isClosing = true;
    return _closeFuture ??= _disposeChannel().whenComplete(_updates.close);
  }
}
