import 'dart:ffi';
import 'package:godot_dart/godot_dart.dart';

part 'hatch_fx.g.dart';

@GodotScript()
class HatchFX extends Node2D {
  @override
  late final ExtensionTypeInfo<HatchFX> typeInfo = HatchFX.sTypeInfo;

  @pragma('vm:entry-point')
  static final ExtensionTypeInfo<HatchFX> sTypeInfo = _$HatchFXTypeInfo();

  HatchFX() : super();
  HatchFX.withNonNullOwner(Pointer<Void> owner) : super.withNonNullOwner(owner);

  double radius = 110.0;

  @override
  void vDraw() {
    drawCircle(Vector2(x: 0, y: 0), radius, Color.fromRGBA(1, 1, 1, 1));
  }
}
