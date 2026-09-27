import '../domain/wash_state.dart';

/// Transport-independent updates. The BLoC builds its application state from them.
sealed class WasherUpdate {
  const WasherUpdate();
}

final class WasherConnectionChanged extends WasherUpdate {
  final bool connected;
  final String? error;
  const WasherConnectionChanged(this.connected, {this.error});
}

final class WasherStateReceived extends WasherUpdate {
  final WashState state;
  const WasherStateReceived(this.state);
}

final class WasherFailure extends WasherUpdate {
  final String message;
  const WasherFailure(this.message);
}

/// A single owned connection. Subscribe before connect; close when its owner exits.
/// Updates are notifications, not a replay of the last application state.
abstract interface class WasherRepository {
  Stream<WasherUpdate> get updates;
  Future<void> connect();
  Future<void> disconnect();
  void start();
  void reset();
  Future<void> close();
}
