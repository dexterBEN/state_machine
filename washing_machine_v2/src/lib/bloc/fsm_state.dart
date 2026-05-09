import 'model.dart';

class FsmState {
  final bool connected;
  final WashState washState;
  final String? lastError;

  const FsmState({
    required this.connected,
    required this.washState,
    this.lastError,
  });

  FsmState copyWith({
    bool? connected,
    WashState? washState,
    String? lastError,
  }) => FsmState(
    connected: connected ?? this.connected, 
    washState: washState ?? this.washState, 
    lastError: lastError
  );

  static const initial = FsmState(
    connected: false,
    washState: WashState.idle
  );
}