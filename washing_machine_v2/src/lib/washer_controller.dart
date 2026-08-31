import 'dart:ffi';

import 'package:godot_dart/godot_dart.dart';

import 'package:godot_dart_example/bloc/model.dart';
import 'package:godot_dart_example/bloc/fsm_event.dart';
import 'package:godot_dart_example/bloc/fsm_bloc.dart';
import 'washer_hatch.dart';

part 'washer_controller.g.dart';

@GodotScript()
class WasherController extends Node {
  @override
  ExtensionTypeInfo<WasherController> get typeInfo => WasherController.sTypeInfo;

  @pragma('vm:entry-point')
  static ExtensionTypeInfo<WasherController> get sTypeInfo => _$WasherControllerTypeInfo();

  WasherController() : super();
  WasherController.withNonNullOwner(Pointer<Void> owner) : super.withNonNullOwner(owner);

  // websocket IP
  String wsUrl = "ws://192.168.200.111:8765";

  NodePath hatchPath = NodePath.fromString("../WasherHatch");

  late final FsmBloc bloc;
  WasherHatch? _hatch;

  @override
  void vReady() {
    _hatch = getNodeOrNull(hatchPath) as WasherHatch?;

    bloc = FsmBloc(wsUrl: wsUrl);

    // écoute le flux d'état et pilote le rendu
    bloc.stream.listen((s) {
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
  void start() => bloc.add(StartPressed());
  void reset() => bloc.add(ResetPressed());

  @override
  Future<void> close() async {
    await bloc.close();
    return super.vExitTree();
  }
}