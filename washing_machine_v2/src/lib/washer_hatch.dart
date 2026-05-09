import 'dart:ffi';
import 'dart:math' as math;

import 'package:godot_dart/godot_dart.dart';
import './washer_body.dart';

part 'washer_hatch.g.dart';

/// FSM states (visual side)
enum WasherState { idle, fill, wash, rinse, spin, done }

@GodotScript()
class WasherHatch extends Node2D {
  @override
  late final ExtensionTypeInfo<WasherHatch> typeInfo = WasherHatch.sTypeInfo;

  @pragma('vm:entry-point')
  static final ExtensionTypeInfo<WasherHatch> sTypeInfo = _$WasherHatchTypeInfo();

  WasherHatch() : super();
  WasherHatch.withNonNullOwner(Pointer<Void> owner) : super.withNonNullOwner(owner);

  // --- Scene wiring
  NodePath bodyPath = NodePath.fromString('../WasherBody');
  bool autoAlignEachFrame = true;

  // --- Geometry
  double outerRadius = 88;
  double ringThickness = 14.0;

  // --- Colors (keep your palette)
  final Color rimOuter = Color.fromRGBA(0.80, 0.77, 0.91, 1.0);
  final Color rimInner = Color.fromRGBA(0.70, 0.67, 0.84, 1.0);
  final Color rimSoft = Color.fromRGBA(0.90, 0.87, 0.96, 0.95);

  final Color glassBase = Color.fromRGBA(0.69, 0.75, 0.81, 0.90);
  final Color glassWash = Color.fromRGBA(0.80, 0.86, 0.91, 0.08);

  final Color highlightA = Color.fromRGBA(0.90, 0.95, 0.98, 0.32);
  final Color highlightB = Color.fromRGBA(0.93, 0.97, 0.99, 0.28);

  final Color doorShadow = Color.fromRGBA(0.15, 0.14, 0.22, 0.02);

  // --- Animation / State
  WasherState _state = WasherState.idle;

  double _spinSpeed = 0.0;
  double _targetSpinSpeed = 0.0;
  double _drumAngle = 0.0;

  bool animationsEnabled = true;
  double spinEaseK = 10.0;

  // Water / foam (0..1)
  double _waterLevel = 0.0;
  double _targetWaterLevel = 0.0;
  double waterEaseK = 6.0;

  double _foam = 0.0;
  double _targetFoam = 0.0;
  double foamEaseK = 6.0;

  double _steam = 0.0;
  double _targetSteam = 0.0;
  double steamEaseK = 8.0;

  double _t = 0.0;

  // --- Public API
  void setState(WasherState s) {
    _state = s;

    switch (_state) {
      case WasherState.fill:
        _targetWaterLevel = 0.65;
        _targetFoam = 0.0;
        _targetSpinSpeed = 0.0;
        _targetSteam = 0.0;
        break;

      case WasherState.wash:
        _targetWaterLevel = 0.55;
        _targetFoam = 0.8;
        _targetSpinSpeed = 1.2;
        _targetSteam = 0.0;
        break;

      case WasherState.rinse:
        _targetWaterLevel = 0.60;
        _targetFoam = 0.25;
        _targetSpinSpeed = 1.6;
        _targetSteam = 1.35;
        break;

      case WasherState.spin:
        _targetWaterLevel = 0.10;
        _targetFoam = 0.0;
        _targetSpinSpeed = 5.5;
        _targetSteam = 0.0;
        break;

      // case WasherState.drain:
      //   _targetWaterLevel = 0.0;
      //   _targetFoam = 0.0;
      //   _targetSpinSpeed = 0.4;
      //   _targetSteam = 0.0;
      //   break;

      case WasherState.done:
      case WasherState.idle:
        _targetWaterLevel = 0.0;
        _targetFoam = 0.0;
        _targetSpinSpeed = 0.0;
        _targetSteam = 0.0;
        break;
    }

    queueRedraw();
  }

  WasherState getState() => _state;

  void setTargetSpinSpeed(double radPerSec) => _targetSpinSpeed = radPerSec;
  double getSpinSpeed() => _spinSpeed;

  // --- Lifecycle
  @override
  void vReady() {
    _alignToBody();
    // IMPORTANT: ne force pas un état ici, laisse ton futur controller/bloc piloter.
    queueRedraw();
  }

  @override
  void vProcess(double delta) {
    if (autoAlignEachFrame) _alignToBody();
    if (!animationsEnabled) return;

    _t += delta;

    // Smooth spin
    final aSpin = 1.0 - math.exp(-spinEaseK * delta);
    _spinSpeed = _spinSpeed + (_targetSpinSpeed - _spinSpeed) * aSpin;
    _drumAngle += _spinSpeed * delta;
    if (_drumAngle.abs() > 100000.0) {
      _drumAngle = _drumAngle % (2.0 * math.pi);
    }

    // Smooth water/foam
    final aw = 1.0 - math.exp(-waterEaseK * delta);
    _waterLevel = _waterLevel + (_targetWaterLevel - _waterLevel) * aw;

    final af = 1.0 - math.exp(-foamEaseK * delta);
    _foam = _foam + (_targetFoam - _foam) * af;

    final as = 1.0 - math.exp(-steamEaseK * delta);
    _steam = _steam + (_targetSteam - _steam) * as;

    queueRedraw();
  }

  void _alignToBody() {
    final n = getNodeOrNull(bodyPath);
    if (n is! WasherBody) return;
    setGlobalPosition(n.getHatchCenterWorld());
    setRotation(n.getHatchTiltRad());
    setScale(n.getHatchScale());
  }

  // --- Draw
  @override
  void vDraw() {
    final c = Vector2(x: 0, y: 0);
    final innerR = math.max(0.0, outerRadius - ringThickness);
    final glassR = innerR - 2.5;

    // Door cast shadow
    _drawEllipseFilledLocal(
      center: Vector2(x: 2, y: 4),
      rx: outerRadius * 0.93,
      ry: outerRadius * 0.84,
      color: doorShadow,
      steps: 72,
    );

    // Rims
    drawCircle(c, outerRadius, rimOuter);
    drawCircle(c, outerRadius - 3.0, rimSoft);
    drawCircle(c, innerR, rimInner);
    drawCircle(c, innerR - 2.0, Color.fromRGBA(0.77, 0.75, 0.89, 1.0));

    // Glass base
    drawCircle(c, glassR, glassBase);

    // ✅ Eau + bulles d'abord (pour que le voile unifie ensuite)
    _drawWater(c, glassR - 6.0);
    _drawBubbles(c, glassR - 10.0);

    // Voile de verre ensuite
    drawCircle(c, glassR - 4.0, glassWash);

    // Spin rotor inside the drum (subtle at low speed, strong in spin).
    _drawSpinRotor(c, glassR - 6.0);

    // Highlights au-dessus
    _drawGlassHighlights(c, glassR);

    // Steam only for rinse transition / rinse state.
    _drawSteam(c, outerRadius);
  }

  // --- Water (clipped to ellipse)
  void _drawWater(Vector2 c, double r) {
    if (_waterLevel <= 0.001) return;

    final wobble = (_state == WasherState.wash || _state == WasherState.rinse)
        ? math.sin(_t * 2.0) * 4.0
        : 0.0;

    final rx = r * 0.98;
    final ry = r * 0.84;

    final top = c.y - ry;
    final bot = c.y + ry;

    final lineY = bot - (bot - top) * _waterLevel + wobble;

    final poly = _ellipseSegmentBelowY(c, rx, ry, lineY, steps: 96);
    if (poly.size() < 3) return;

    // ✅ Gradient plus visible
    final cols = PackedColorArray();
    for (int i = 0; i < poly.size(); i++) {
      final p = poly[i];
      final t = ((p.y - top) / (bot - top)).clamp(0.0, 1.0);
      final a = 0.28 + t * 0.32; // 0.28..0.60 (plus présent)
      cols.append(Color.fromRGBA(0.50, 0.70, 0.86, a));
    }
    drawPolygon(poly, cols);

    // ✅ Surface highlight plus lisible
    drawLine(
      Vector2(x: c.x - rx * 0.56, y: lineY),
      Vector2(x: c.x + rx * 0.56, y: lineY),
      Color.fromRGBA(0.90, 0.97, 0.99, 0.22),
      width: 3.0,
      antialiased: true,
    );
  }

  PackedVector2Array _ellipseSegmentBelowY(
    Vector2 center,
    double rx,
    double ry,
    double cutY, {
    int steps = 72,
  }) {
    final ellipse = <Vector2>[];
    for (int i = 0; i < steps; i++) {
      final t = (i / steps) * 2.0 * math.pi;
      ellipse.add(Vector2(
        x: center.x + rx * math.cos(t),
        y: center.y + ry * math.sin(t),
      ));
    }

    final pts = <Vector2>[];
    for (int i = 0; i < ellipse.length; i++) {
      final p0 = ellipse[i];
      final p1 = ellipse[(i + 1) % ellipse.length];

      final below0 = p0.y >= cutY;
      final below1 = p1.y >= cutY;

      if (below0) pts.add(p0);

      if (below0 != below1) {
        final dy = (p1.y - p0.y);
        if (dy.abs() > 1e-6) {
          final tt = (cutY - p0.y) / dy;
          final ix = p0.x + (p1.x - p0.x) * tt;
          pts.add(Vector2(x: ix, y: cutY));
        }
      }
    }

    final out = PackedVector2Array();
    for (final p in pts) {
      out.append(p);
    }
    return out;
  }

  // --- Bubbles
  void _drawBubbles(Vector2 c, double r) {
    if (_foam <= 0.01) return;

    final n = (6 + _foam * 10).toInt();
    for (int i = 0; i < n; i++) {
      final a = (i * 1.7) + _t * 0.6;
      final px = c.x + math.cos(a) * r * (0.15 + (i % 5) * 0.12);
      final py = c.y + math.sin(a * 1.3) * r * (0.10 + (i % 3) * 0.18);
      final rad = 3.0 + (i % 4) * 2.2;

      drawCircle(
        Vector2(x: px, y: py),
        rad,
        Color.fromRGBA(0.95, 0.98, 0.99, 0.08 + _foam * 0.10),
      );
    }
  }

  // --- Glass highlights (slightly animated during spin)
  void _drawGlassHighlights(Vector2 c, double r) {
    var slant = Vector2(x: -0.43, y: 0.90);

    if (_state == WasherState.spin || _spinSpeed > 2.0) {
      final rot = _drumAngle * 0.15;
      final cs = math.cos(rot);
      final sn = math.sin(rot);
      slant = Vector2(
        x: slant.x * cs - slant.y * sn,
        y: slant.x * sn + slant.y * cs,
      );
    }

    final ortho = Vector2(x: -slant.y, y: slant.x);

    final base = c + Vector2(x: -r * 0.08, y: -r * 0.03);
    final lenA = r * 0.84;
    final lenB = r * 0.46;
    final wA = r * 0.12;
    final wB = r * 0.036;

    final a0 = base + slant * (-lenA * 0.52) + ortho * wA;
    final a1 = base + slant * (lenA * 0.48) + ortho * wA;
    final a2 = base + slant * (lenA * 0.48) - ortho * wA;
    final a3 = base + slant * (-lenA * 0.52) - ortho * wA;
    _drawQuad(a0, a1, a2, a3, highlightA);

    final base2 = base + Vector2(x: r * 0.27, y: -r * 0.06);
    final b0 = base2 + slant * (-lenB * 0.52) + ortho * wB;
    final b1 = base2 + slant * (lenB * 0.48) + ortho * wB;
    final b2 = base2 + slant * (lenB * 0.48) - ortho * wB;
    final b3 = base2 + slant * (-lenB * 0.52) - ortho * wB;
    _drawQuad(b0, b1, b2, b3, highlightB);

    final base3 = base2 + Vector2(x: r * 0.06, y: -r * 0.01);
    final lenC = r * 0.42;
    final wC = r * 0.028;
    final c0 = base3 + slant * (-lenC * 0.52) + ortho * wC;
    final c1 = base3 + slant * (lenC * 0.48) + ortho * wC;
    final c2 = base3 + slant * (lenC * 0.48) - ortho * wC;
    final c3 = base3 + slant * (-lenC * 0.52) - ortho * wC;
    _drawQuad(c0, c1, c2, c3, Color.fromRGBA(0.93, 0.97, 0.99, 0.07));
  }

  void _drawSteam(Vector2 c, double r) {
    if (_steam <= 0.01) return;

    final innerR = math.max(0.0, r - ringThickness - 8.0);
    final plumeCount = 10;
    for (int i = 0; i < plumeCount; i++) {
      final phase = _t * 2.0 + i * 0.72;
      final ring = 0.18 + (i % 5) * 0.12;
      final swirl = phase + i * 0.35;
      final x = c.x + math.cos(swirl) * innerR * ring * 0.95;
      final y = c.y + math.sin(swirl * 1.15) * innerR * ring * 0.75 - innerR * 0.10;
      final rx = 9.0 + (i % 4) * 2.1;
      final ry = 5.0 + (i % 3) * 1.4;
      final alpha = (0.16 + i * 0.010) * _steam;

      _drawEllipseFilledLocal(
        center: Vector2(x: x, y: y),
        rx: rx,
        ry: ry,
        color: Color.fromRGBA(0.90, 0.95, 0.99, alpha),
        steps: 42,
      );

      // Inner brighter core to keep the steam visible inside the glass.
      _drawEllipseFilledLocal(
        center: Vector2(x: x + 0.4, y: y - 0.5),
        rx: rx * 0.52,
        ry: ry * 0.52,
        color: Color.fromRGBA(0.98, 0.99, 1.0, alpha * 0.62),
        steps: 32,
      );
    }

    // Base mist inside the hatch.
    _drawEllipseFilledLocal(
      center: Vector2(x: c.x, y: c.y + innerR * 0.06),
      rx: innerR * 0.82,
      ry: innerR * 0.32,
      color: Color.fromRGBA(0.86, 0.93, 0.98, 0.24 * _steam),
      steps: 56,
    );
  }

  void _drawSpinRotor(Vector2 c, double r) {
    final speedN = (_spinSpeed / 5.5).clamp(0.0, 1.0);
    if (speedN <= 0.04) return;

    final bladeCount = 3;
    final hubR = r * (0.11 + speedN * 0.03);
    final bladeLen = r * (0.64 + speedN * 0.08);
    final w0 = r * (0.14 + speedN * 0.04);
    final w1 = r * (0.06 + speedN * 0.02);
    final bladeAlpha = 0.15 + speedN * 0.24;

    for (int i = 0; i < bladeCount; i++) {
      final a = _drumAngle + i * (2.0 * math.pi / bladeCount);
      final dir = Vector2(x: math.cos(a), y: math.sin(a));
      final ortho = Vector2(x: -dir.y, y: dir.x);

      final s = c + dir * hubR;
      final e = c + dir * bladeLen;

      final p0 = s + ortho * w0;
      final p1 = e + ortho * w1;
      final p2 = e - ortho * w1;
      final p3 = s - ortho * w0;

      _drawQuad(p0, p1, p2, p3, Color.fromRGBA(0.76, 0.86, 0.97, bladeAlpha));
    }

    // Central cap and light blur ring to emphasize fast spin.
    drawCircle(c, hubR, Color.fromRGBA(0.86, 0.93, 0.98, 0.28 + speedN * 0.20));
    _drawEllipseFilledLocal(
      center: c,
      rx: r * 0.78,
      ry: r * 0.66,
      color: Color.fromRGBA(0.82, 0.90, 0.97, 0.03 + speedN * 0.08),
      steps: 48,
    );
  }

  // --- helpers
  void _drawQuad(Vector2 p0, Vector2 p1, Vector2 p2, Vector2 p3, Color c) {
    final pts = PackedVector2Array();
    pts.append(p0);
    pts.append(p1);
    pts.append(p2);
    pts.append(p3);
    drawColoredPolygon(pts, c);
  }

  void _drawEllipseFilledLocal({
    required Vector2 center,
    required double rx,
    required double ry,
    required Color color,
    int steps = 64,
  }) {
    final pts = PackedVector2Array();
    for (int i = 0; i < steps; i++) {
      final t = (i / steps) * (2.0 * math.pi);
      pts.append(Vector2(
        x: center.x + rx * math.cos(t),
        y: center.y + ry * math.sin(t),
      ));
    }
    drawColoredPolygon(pts, color);
  }
}
