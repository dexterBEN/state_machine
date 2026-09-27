import 'dart:async';
import 'dart:ffi';

import 'package:godot_dart/godot_dart.dart';

import 'domain/wash_state.dart';
import 'repository/web_socket_washer_repository.dart';
import 'bloc/fsm_state.dart';
import 'bloc/fsm_event.dart';
import 'bloc/fsm_bloc.dart';
import 'washer_hatch.dart';

part 'washer_controller.g.dart';

@GodotScript()
class WasherController extends Node {
  @override
  ExtensionTypeInfo<WasherController> get typeInfo =>
      WasherController.sTypeInfo;

  @pragma('vm:entry-point')
  static ExtensionTypeInfo<WasherController> get sTypeInfo =>
      _$WasherControllerTypeInfo();

  WasherController() : super();
  WasherController.withNonNullOwner(Pointer<Void> owner)
      : super.withNonNullOwner(owner);

  // websocket IP
  String wsUrl = 'ws://192.168.200.107:8765';

  NodePath hatchPath = NodePath.fromString('../WasherHatch');

  FsmBloc? _bloc;
  StreamSubscription<FsmState>? _stateSubscription;
  WasherHatch? _hatch;

  @override
  void vReady() {
    _hatch = getNodeOrNull(hatchPath) as WasherHatch?;

    final bloc = FsmBloc(
      repository: WebSocketWasherRepository(wsUrl: wsUrl),
    );
    _bloc = bloc;

    // écoute le flux d'état et pilote le rendu
    _stateSubscription = bloc.stream.listen((s) {
      _hatch?.setState(_mapToVisual(s.washState));
    });

    bloc.add(ConnectRequested());
  }

  WasherState _mapToVisual(WashState s) {
    switch (s) {
      case WashState.idle:
        return WasherState.idle;
      case WashState.fill:
        return WasherState.fill;
      case WashState.wash:
        return WasherState.wash;
      case WashState.rinse:
        return WasherState.rinse;
      case WashState.spin:
        return WasherState.spin;
      case WashState.done:
        return WasherState.done;
    }
  }

  // pour boutons Godot (later in UI)
  void start() => _bloc?.add(StartPressed());
  void reset() => _bloc?.add(ResetPressed());

  @override
  void vExitTree() {
    final subscription = _stateSubscription;
    final bloc = _bloc;
    // Detach the view immediately: Godot does not await asynchronous cleanup.
    _stateSubscription = null;
    _bloc = null;
    _hatch = null;
    unawaited(_dispose(subscription, bloc));
    super.vExitTree();
  }

  static Future<void> _dispose(
    StreamSubscription<FsmState>? subscription,
    FsmBloc? bloc,
  ) async {
    try {
      try {
        await subscription?.cancel();
      } finally {
        await bloc?.close();
      }
    } catch (error, stackTrace) {
      // Use Dart logging here; the native Godot node may already be destroyed.
      print('WasherController cleanup failed: $error\n$stackTrace');
    }
  }
}
