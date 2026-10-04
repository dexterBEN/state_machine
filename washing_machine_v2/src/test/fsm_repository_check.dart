// Run with: dart run test/fsm_repository_check.dart
import 'dart:async';

import 'package:godot_dart_example/bloc/fsm_bloc.dart';
import 'package:godot_dart_example/bloc/fsm_event.dart';
import 'package:godot_dart_example/domain/wash_state.dart';
import 'package:godot_dart_example/repository/washer_repository.dart';

import 'fsm_lifecycle_check.dart' as integration;

/// No networking: proves that the BLoC depends only on the repository contract.
class FakeWasherRepository implements WasherRepository {
  final controller = StreamController<WasherUpdate>.broadcast();
  final calls = <String>[];
  int closeCount = 0;
  bool listenedWhenClosed = false;

  @override
  Stream<WasherUpdate> get updates => controller.stream;
  @override
  Future<void> connect() async {
    calls.add('connect');
    controller.add(const WasherConnectionChanged(true));
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    controller.add(const WasherConnectionChanged(false));
  }

  @override
  void start() => calls.add('start');
  @override
  void reset() => calls.add('reset');
  @override
  Future<void> close() async {
    closeCount++;
    listenedWhenClosed = controller.hasListener;
    await controller.close();
  }
}

Future<void> checkFakeRepository() async {
  final repository = FakeWasherRepository();
  final bloc = FsmBloc(repository: repository);
  try {
    final connected = bloc.stream.firstWhere((s) => s.connected);
    bloc.add(StartPressed()); // Ignored while disconnected.
    bloc.add(ResetPressed());
    bloc.add(ConnectRequested());
    await connected;
    integration.check(repository.calls.join(',') == 'connect',
        'Disconnected commands reached the repository');

    final washing =
        bloc.stream.firstWhere((s) => s.washState == WashState.wash);
    repository.controller.add(const WasherStateReceived(WashState.wash));
    await washing;
    final failure = bloc.stream.firstWhere((s) => s.lastError != null);
    repository.controller.add(const WasherFailure('Sample failure'));
    await failure;
    integration.check(
        bloc.state.washState == WashState.wash && bloc.state.connected,
        'An error replaced the current wash state or connection');

    final disconnected = bloc.stream.firstWhere((s) => !s.connected);
    bloc.add(StartPressed());
    bloc.add(ResetPressed());
    bloc.add(DisconnectRequested());
    await disconnected;
    integration.check(
        repository.calls.join(',') == 'connect,start,reset,disconnect',
        'Commands were not delegated in order');
    integration.check(bloc.state.washState == WashState.wash,
        'Commands must not advance the machine state locally');

    final closing = bloc.close();
    await closing;
    await bloc.close();
    integration.check(
        repository.closeCount == 1, 'Repository closed more than once');
    integration.check(!repository.listenedWhenClosed,
        'Repository listener was not cancelled');
    print(
        'PASS: BLoC with fake repository: states, errors, commands and ownership');
  } finally {
    await bloc.close();
  }
}

Future<void> main() async {
  await checkFakeRepository().timeout(const Duration(seconds: 5));

  await integration.scenario('WebSocket commands retain the backend protocol',
      (server, bloc) async {
    final peer = await server.connect(bloc);
    final commands = peer.messages.stream.take(2).toList();
    bloc.add(StartPressed());
    bloc.add(ResetPressed());
    integration.check((await commands).join(',') == 'START,RESET',
        'Unexpected WebSocket command format');
  });

  await integration.scenario('decode JSON and text; reject malformed states',
      (server, bloc) async {
    final peer = await server.connect(bloc);
    final washing =
        bloc.stream.firstWhere((s) => s.washState == WashState.wash);
    peer.socket.add('{"type":"state","value":"WASH"}');
    await washing;

    for (final invalid in ['not a state', '{"type":"state","value":42}']) {
      final failure = bloc.stream.firstWhere((s) => s.lastError != null);
      peer.socket.add(invalid);
      await failure;
      integration.check(
          bloc.state.washState == WashState.wash && bloc.state.connected,
          'Invalid input changed the wash state or dropped the connection');
    }

    final recorded = <WashState>[];
    final listener = bloc.stream.listen((s) => recorded.add(s.washState));
    try {
      final spinning =
          bloc.stream.firstWhere((s) => s.washState == WashState.spin);
      peer.socket.add('{"type":"heartbeat"}');
      peer.socket.add(' SPIN ');
      await spinning;
      integration.check(
          recorded.length == 1 && recorded.single == WashState.spin,
          'An unrelated message altered the state');
      integration.check(
          bloc.state.lastError == null, 'Valid input did not clear the error');
    } finally {
      await listener.cancel();
    }
  });
}
