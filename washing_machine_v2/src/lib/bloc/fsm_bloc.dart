import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'fsm_state.dart';
import 'fsm_event.dart';
import 'model.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FsmBloc extends Bloc<FsmEvent, FsmState> {
  final String wsUrl;
  WebSocketChannel? _channel;

  FsmBloc({required this.wsUrl}) : super(FsmState.initial) {
    on<ConnectRequested>(_onConnect);
    on<DisconnectRequested>(_onDisconnect);

    on<StartPressed>(_onStartPressed);
    on<ResetPressed>(_onResetPressed);

    on<RawMessageReceived>(_onRawMessage);
  }

  void _sendCmd(String cmd) {
    _channel?.sink.add(cmd);
  }

  void _onStartPressed(StartPressed e, Emitter<FsmState> emit) {
    if (!state.connected) return;
    _sendCmd("START");
  }

  void _onResetPressed(ResetPressed e, Emitter<FsmState> emit) {
    if (!state.connected) return;
    _sendCmd("RESET");
  }

  void _onRawMessage(RawMessageReceived e, Emitter<FsmState> emit) {
    try {
      final obj = jsonDecode(e.raw) as Map<String, dynamic>;
      if (obj["type"] == "state") {
        final v = obj["value"] as String;
        emit(state.copyWith(washState: parseWashState(v)));
      }
    } catch (_) {
      emit(state.copyWith(washState: parseWashState(e.raw.trim())));
    }
  }

  Future<void> _onConnect(ConnectRequested e, Emitter<FsmState> emit) async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      emit(state.copyWith(connected: true));

      _channel!.stream.listen(
        (msg) => add(RawMessageReceived(msg as String)),
        onError: (_) => add(DisconnectRequested()),
        onDone: () => add(DisconnectRequested()),
      );
    } catch (err) {
      emit(state.copyWith(connected: false, lastError: err.toString()));
    }
  }

  Future<void> _onDisconnect(DisconnectRequested e, Emitter<FsmState> emit) async {
    _channel?.sink.close();
    _channel = null;
    emit(state.copyWith(connected: false));
  }
}