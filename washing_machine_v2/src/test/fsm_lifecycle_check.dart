// Standalone integration checks: dart run test/fsm_lifecycle_check.dart
// Uses a local WebSocket server, without Godot, the FPGA, or extra packages.
import 'dart:async';
import 'dart:io';

import 'package:godot_dart_example/bloc/fsm_bloc.dart';
import 'package:godot_dart_example/bloc/fsm_event.dart';
import 'package:godot_dart_example/repository/web_socket_washer_repository.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

class Peer {
  final WebSocket socket;
  final done = Completer<void>();
  final messages = StreamController<String>.broadcast();

  Peer(this.socket) {
    socket.listen((message) {
      if (message is String) messages.add(message);
    }, onDone: () {
      done.complete();
      unawaited(messages.close());
    });
  }
}

class LocalServer {
  final HttpServer server;
  final peers = StreamController<Peer>.broadcast();
  final accepted = <Peer>[];
  final requestReceived = Completer<void>();
  Completer<void>? handshakeGate;

  LocalServer(this.server) {
    server.listen((request) async {
      if (!requestReceived.isCompleted) requestReceived.complete();
      await handshakeGate?.future;
      final peer = Peer(await WebSocketTransformer.upgrade(request));
      accepted.add(peer);
      peers.add(peer);
    });
  }

  String get url => 'ws://127.0.0.1:${server.port}';

  Future<Peer> connect(FsmBloc bloc) async {
    final nextPeer = peers.stream.first;
    final connected = bloc.stream.firstWhere((s) => s.connected);
    bloc.add(ConnectRequested());
    final peer = await nextPeer;
    await connected;
    return peer;
  }

  Future<void> close() async {
    for (final peer in accepted) {
      await peer.socket.close();
    }
    await peers.close();
    await server.close(force: true);
  }
}

Future<void> scenario(
  String name,
  Future<void> Function(LocalServer server, FsmBloc bloc) body,
) async {
  final server =
      LocalServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
  final bloc =
      FsmBloc(repository: WebSocketWasherRepository(wsUrl: server.url));
  try {
    await body(server, bloc).timeout(const Duration(seconds: 5));
    print('PASS: $name');
  } finally {
    if (server.handshakeGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    await bloc.close();
    await server.close();
  }
}

Future<void> main() async {
  await scenario('close closes the peer and state stream; repeat close is safe',
      (server, bloc) async {
    final peer = await server.connect(bloc);
    final streamDone = Completer<void>();
    var updates = 0;
    bloc.stream.listen((_) => updates++, onDone: streamDone.complete);
    peer.socket.add('WASH');
    final first = bloc.close();
    check(
        identical(first, bloc.close()), 'close must share its pending future');
    await first;
    await peer.done.future;
    await streamDone.future;
    check(bloc.isClosed, 'BLoC must be closed');
    check(updates == 0, 'Late messages must not update the closed scene');
  });

  await scenario('close before a queued connect does not open a socket',
      (server, bloc) async {
    bloc.add(ConnectRequested());
    await bloc.close();
    check(
        server.accepted.isEmpty, 'Queued connect opened a socket after close');
  });

  await scenario('close during handshake closes the eventual connection',
      (server, bloc) async {
    server.handshakeGate = Completer<void>();
    final nextPeer = server.peers.stream.first;
    var connected = false;
    bloc.stream.listen((s) => connected |= s.connected);
    bloc.add(ConnectRequested());
    await server.requestReceived.future;
    final closing = bloc.close();
    server.handshakeGate!.complete();
    final peer = await nextPeer;
    await closing;
    await peer.done.future;
    check(!connected, 'A pending connection published state after close');
  });

  await scenario('disconnect releases the socket and permits reconnection',
      (server, bloc) async {
    final first = await server.connect(bloc);
    final disconnected = bloc.stream.firstWhere((s) => !s.connected);
    bloc.add(DisconnectRequested());
    await disconnected;
    await first.done.future;
    final second = await server.connect(bloc);
    final remoteDisconnected = bloc.stream.firstWhere((s) => !s.connected);
    await second.socket.close();
    await remoteDisconnected;
    await bloc.close();
  });

  final invalid =
      FsmBloc(repository: WebSocketWasherRepository(wsUrl: 'ws://['));
  final failed = invalid.stream.firstWhere((s) => s.lastError != null);
  invalid.add(ConnectRequested());
  await failed.timeout(const Duration(seconds: 5));
  await invalid.close();
  print('PASS: invalid URL remains handled and closable');
}
