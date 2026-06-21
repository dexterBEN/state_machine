import 'dart:ffi';
import 'dart:math' as math;
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

  double radius = 78.0;
  double phase = 0.0;

  @override
  void vProcess(double delta) {
    phase += delta * 0.8;
    queueRedraw();
  }

  @override
  void vDraw() {
    final rx = radius;
    final ry = radius * 0.78;

    _drawEllipse(
      Vector2(x: 4, y: 5),
      rx + 11,
      ry + 11,
      Color.fromRGBA(0.42, 0.34, 0.60, 0.12),
    );

    _drawEllipse(
      Vector2(x: 0, y: 0),
      rx + 10,
      ry + 10,
      Color.fromRGBA(0.79, 0.73, 0.96, 0.95),
    );

    _drawEllipse(
      Vector2(x: 0, y: 0),
      rx + 3,
      ry + 3,
      Color.fromRGBA(0.88, 0.83, 0.98, 1.0),
    );

    _drawEllipse(
      Vector2(x: 0, y: 0),
      rx - 7,
      ry - 7,
      Color.fromRGBA(0.62, 0.72, 0.79, 0.78),
    );

    _drawEllipse(
      Vector2(x: -4, y: -3),
      rx - 15,
      ry - 15,
      Color.fromRGBA(0.52, 0.63, 0.72, 0.35),
    );

    _drawGlassReflection(rx, ry);
  }

  void _drawGlassReflection(double rx, double ry) {
    final offset = math.sin(phase) * 4.0;

    final col1 = Color.fromRGBA(0.90, 0.96, 1.0, 0.28);
    final col2 = Color.fromRGBA(0.90, 0.96, 1.0, 0.16);

    _drawSlantedQuad(
      Vector2(x: -16 + offset, y: -38),
      Vector2(x: 5 + offset, y: -33),
      Vector2(x: -18 + offset, y: 38),
      Vector2(x: -39 + offset, y: 32),
      col1,
    );

    _drawSlantedQuad(
      Vector2(x: 10 + offset, y: -34),
      Vector2(x: 18 + offset, y: -31),
      Vector2(x: -6 + offset, y: 32),
      Vector2(x: -14 + offset, y: 29),
      col2,
    );
  }

  void _drawEllipse(Vector2 c, double rx, double ry, Color col) {
    const steps = 72;
    final pts = PackedVector2Array();

    for (int i = 0; i < steps; i++) {
      final t = (i / steps) * 2 * math.pi;
      pts.append(Vector2(
        x: c.x + rx * math.cos(t),
        y: c.y + ry * math.sin(t),
      ));
    }

    drawColoredPolygon(pts, col);
  }

  void _drawSlantedQuad(Vector2 p0, Vector2 p1, Vector2 p2, Vector2 p3, Color c) {
    final pts = PackedVector2Array();
    pts.append(p0);
    pts.append(p1);
    pts.append(p2);
    pts.append(p3);
    drawColoredPolygon(pts, c);
  }
}