import 'dart:ffi';
import 'dart:math' as math;

import 'package:godot_dart/godot_dart.dart';
import './washer_body.dart';

part 'washer_hatch.g.dart';

/// FSM states on the visual/frontend side.
///
/// This enum should stay aligned with the VHDL FSM state_code mapping:
/// 0 = idle
/// 1 = fill
/// 2 = wash
/// 3 = rinse
/// 4 = spin
/// 5 = done
enum WasherState { idle, fill, wash, rinse, spin, done }

@GodotScript()
class WasherHatch extends Node2D {
  @override
  late final ExtensionTypeInfo<WasherHatch> typeInfo = WasherHatch.sTypeInfo;

  @pragma('vm:entry-point')
  static final ExtensionTypeInfo<WasherHatch> sTypeInfo =
      _$WasherHatchTypeInfo();

  WasherHatch() : super();

  WasherHatch.withNonNullOwner(Pointer<Void> owner)
      : super.withNonNullOwner(owner);

  // ---------------------------------------------------------------------------
  // Scene wiring
  // ---------------------------------------------------------------------------

  /// The WasherBody node is used as the geometric reference.
  ///
  /// WasherBody gives us:
  /// - hatch center
  /// - hatch tilt
  /// - hatch scale
  NodePath bodyPath = NodePath.fromString('../WasherBody');

  /// Keep true while you are tweaking WasherBody geometry.
  /// Once the layout is stable, this can be set to false for fewer updates.
  bool autoAlignEachFrame = true;

  // ---------------------------------------------------------------------------
  // Geometry
  // ---------------------------------------------------------------------------

  /// Keeps the hatch visible without making it too heavy on the front face.
  double outerRadius = 80.0;

  /// Slightly thinner ring for a softer pastel contour.
  double ringThickness = 11.5;

  /// The local drawing is intentionally circular.
  ///
  /// The isometric squash is applied by WasherBody through:
  /// setScale(n.getHatchScale()).
  ///
  /// This keeps the hatch reusable and lets the body decide how much
  /// perspective/tilt to apply.
  double glassInset = 4.0;

  // ---------------------------------------------------------------------------
  // Palette
  // ---------------------------------------------------------------------------

  // Pastel rim colors.
  final Color rimShadow = Color.fromRGBA(0.38, 0.30, 0.52, 0.14);
  final Color rimOuter = Color.fromRGBA(0.78, 0.71, 0.97, 1.0);
  final Color rimSoft = Color.fromRGBA(0.91, 0.86, 1.0, 1.0);
  final Color rimInner = Color.fromRGBA(0.61, 0.55, 0.80, 1.0);
  final Color rimInnerLight = Color.fromRGBA(0.82, 0.78, 0.93, 1.0);

  // Glass colors.
  final Color glassBase = Color.fromRGBA(0.57, 0.70, 0.81, 0.90);
  final Color glassShade = Color.fromRGBA(0.25, 0.35, 0.47, 0.16);
  final Color glassWash = Color.fromRGBA(0.90, 0.96, 1.0, 0.16);

  // Highlights.
  final Color highlightA = Color.fromRGBA(0.96, 0.99, 1.0, 0.44);
  final Color highlightB = Color.fromRGBA(0.98, 0.995, 1.0, 0.28);
  final Color highlightC = Color.fromRGBA(0.96, 0.99, 1.0, 0.12);

  // Liquids / bubbles.
  final Color waterTop = Color.fromRGBA(0.64, 0.80, 0.92, 0.30);
  final Color waterBottom = Color.fromRGBA(0.42, 0.63, 0.80, 0.52);
  final Color bubbleCol = Color.fromRGBA(0.96, 0.99, 1.0, 0.16);

  // Rotor / spin blur.
  final Color rotorCol = Color.fromRGBA(0.77, 0.87, 0.97, 0.28);
  final Color rotorFastCol = Color.fromRGBA(0.84, 0.92, 0.99, 0.18);

  // Steam / mist.
  final Color steamCol = Color.fromRGBA(0.90, 0.96, 0.99, 0.14);
  final Color steamCoreCol = Color.fromRGBA(0.98, 0.995, 1.0, 0.10);

  // ---------------------------------------------------------------------------
  // Animation / State
  // ---------------------------------------------------------------------------

  WasherState _state = WasherState.idle;

  double _spinSpeed = 0.0;
  double _targetSpinSpeed = 0.0;
  double _drumAngle = 0.0;

  bool animationsEnabled = true;

  /// Higher = faster interpolation to the target spin speed.
  double spinEaseK = 10.0;

  /// Water amount from 0 to 1.
  double _waterLevel = 0.0;
  double _targetWaterLevel = 0.0;
  double waterEaseK = 6.0;

  /// Foam/bubbles amount from 0 to 1.
  double _foam = 0.0;
  double _targetFoam = 0.0;
  double foamEaseK = 6.0;

  /// Steam/mist amount from 0 to roughly 1.
  double _steam = 0.0;
  double _targetSteam = 0.0;
  double steamEaseK = 8.0;

  /// Generic time accumulator for procedural effects.
  double _t = 0.0;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void setState(WasherState s) {
    _state = s;

    switch (_state) {
      case WasherState.idle:
        _targetWaterLevel = 0.0;
        _targetFoam = 0.0;
        _targetSpinSpeed = 0.0;
        _targetSteam = 0.0;
        break;

      case WasherState.fill:
        _targetWaterLevel = 0.58;
        _targetFoam = 0.0;
        _targetSpinSpeed = 0.0;
        _targetSteam = 0.0;
        break;

      case WasherState.wash:
        _targetWaterLevel = 0.52;
        _targetFoam = 0.65;
        _targetSpinSpeed = 1.15;
        _targetSteam = 0.0;
        break;

      case WasherState.rinse:
        _targetWaterLevel = 0.56;
        _targetFoam = 0.22;
        _targetSpinSpeed = 1.45;
        _targetSteam = 0.85;
        break;

      case WasherState.spin:
        _targetWaterLevel = 0.08;
        _targetFoam = 0.0;
        _targetSpinSpeed = 5.2;
        _targetSteam = 0.0;
        break;

      case WasherState.done:
        _targetWaterLevel = 0.0;
        _targetFoam = 0.0;
        _targetSpinSpeed = 0.0;
        _targetSteam = 0.0;
        break;
    }

    queueRedraw();
  }

  WasherState getState() => _state;

  void setTargetSpinSpeed(double radPerSec) {
    _targetSpinSpeed = radPerSec;
  }

  double getSpinSpeed() => _spinSpeed;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void vReady() {
    _alignToBody();

    // do not force an initial state here.
    // controller / BLoC / WebSocket layer should drive the state.
    queueRedraw();
  }

  @override
  void vProcess(double delta) {
    if (autoAlignEachFrame) {
      _alignToBody();
    }

    if (!animationsEnabled) {
      return;
    }

    _t += delta;

    // Smooth spin speed.
    final aSpin = 1.0 - math.exp(-spinEaseK * delta);
    _spinSpeed = _spinSpeed + (_targetSpinSpeed - _spinSpeed) * aSpin;

    _drumAngle += _spinSpeed * delta;
    if (_drumAngle.abs() > 100000.0) {
      _drumAngle = _drumAngle % (2.0 * math.pi);
    }

    // Smooth water.
    final aw = 1.0 - math.exp(-waterEaseK * delta);
    _waterLevel = _waterLevel + (_targetWaterLevel - _waterLevel) * aw;

    // Smooth foam.
    final af = 1.0 - math.exp(-foamEaseK * delta);
    _foam = _foam + (_targetFoam - _foam) * af;

    // Smooth steam.
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

  // ---------------------------------------------------------------------------
  // Draw
  // ---------------------------------------------------------------------------

  @override
  void vDraw() {
    final c = Vector2(x: 0, y: 0);

    final innerR = math.max(0.0, outerRadius - ringThickness);
    final glassR = math.max(0.0, innerR - glassInset);

    // Soft cast shadow behind the door.
    _drawEllipseFilledLocal(
      center: Vector2(x: 4.5, y: 5.8),
      rx: outerRadius * 1.03,
      ry: outerRadius * 0.91,
      color: rimShadow,
      steps: 72,
    );

    // Main rim stack.
    drawCircle(c + Vector2(x: 0.9, y: 1.3), outerRadius, rimOuter);
    drawCircle(c + Vector2(x: -1.4, y: -1.5), outerRadius - 3.2, rimSoft);
    drawCircle(c + Vector2(x: 0.4, y: 0.4), outerRadius - 6.7, rimOuter);
    drawCircle(c + Vector2(x: 1.0, y: 1.2), innerR + 1.2, rimInner);
    drawCircle(c + Vector2(x: -0.8, y: -1.1), innerR - 0.4, rimInnerLight);
    drawCircle(c, innerR - 2.8, Color.fromRGBA(0.72, 0.67, 0.89, 1.0));

    // Glass base.
    drawCircle(c, glassR, glassBase);

    // Soft inner shades to avoid a flat circle.
    drawCircle(
      c + Vector2(x: 7.0, y: 7.0),
      glassR * 0.90,
      Color.fromRGBA(0.22, 0.32, 0.44, 0.10),
    );

    drawCircle(
      c + Vector2(x: -5.0, y: 3.0),
      glassR * 0.78,
      glassShade,
    );

    drawCircle(
      c + Vector2(x: -7.0, y: -7.0),
      glassR * 0.54,
      Color.fromRGBA(0.86, 0.95, 1.0, 0.10),
    );

    // Water and bubbles are drawn before the glass veil.
    _drawWater(c, glassR - 6.0);
    _drawBubbles(c, glassR - 10.0);

    // Slight glass veil above water/foam.
    drawCircle(c + Vector2(x: -1.5, y: -2.0), glassR - 4.0, glassWash);

    // Rotor / motion blur.
    _drawSpinRotor(c, glassR - 6.0);

    // Highlights above everything.
    _drawGlassHighlights(c, glassR);

    // Steam / mist.
    _drawSteam(c, outerRadius);
  }

  // ---------------------------------------------------------------------------
  // Water
  // ---------------------------------------------------------------------------

  void _drawWater(Vector2 c, double r) {
    if (_waterLevel <= 0.001) return;

    final shouldWobble =
        _state == WasherState.wash || _state == WasherState.rinse;

    final wobble = shouldWobble ? math.sin(_t * 2.1) * 3.2 : 0.0;

    final rx = r * 0.96;
    final ry = r * 0.82;

    final top = c.y - ry;
    final bot = c.y + ry;

    final lineY = bot - (bot - top) * _waterLevel + wobble;

    final poly = _ellipseSegmentBelowY(c, rx, ry, lineY, steps: 96);
    if (poly.size() < 3) return;

    final cols = PackedColorArray();
    for (int i = 0; i < poly.size(); i++) {
      final p = poly[i];
      final tt = ((p.y - top) / (bot - top)).clamp(0.0, 1.0);

      final a = 0.24 + tt * 0.28;
      final col = Color.fromRGBA(
        waterTop.r + (waterBottom.r - waterTop.r) * tt,
        waterTop.g + (waterBottom.g - waterTop.g) * tt,
        waterTop.b + (waterBottom.b - waterTop.b) * tt,
        a,
      );

      cols.append(col);
    }

    drawPolygon(poly, cols);

    // Water surface highlight.
    drawLine(
      Vector2(x: c.x - rx * 0.52, y: lineY),
      Vector2(x: c.x + rx * 0.52, y: lineY),
      Color.fromRGBA(0.92, 0.98, 1.0, 0.20),
      width: 2.4,
      antialiased: true,
    );

    // Small secondary wave during wash/rinse.
    if (shouldWobble) {
      final waveY = lineY + math.sin(_t * 3.4) * 2.0 + 5.0;
      drawLine(
        Vector2(x: c.x - rx * 0.36, y: waveY),
        Vector2(x: c.x + rx * 0.34, y: waveY + math.cos(_t * 2.0) * 1.5),
        Color.fromRGBA(0.92, 0.98, 1.0, 0.08),
        width: 1.4,
        antialiased: true,
      );
    }
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

      if (below0) {
        pts.add(p0);
      }

      if (below0 != below1) {
        final dy = p1.y - p0.y;

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

  // ---------------------------------------------------------------------------
  // Bubbles
  // ---------------------------------------------------------------------------

  void _drawBubbles(Vector2 c, double r) {
    if (_foam <= 0.01) return;

    final n = (5 + _foam * 9).toInt();

    for (int i = 0; i < n; i++) {
      final a = (i * 1.73) + _t * 0.7;
      final px = c.x + math.cos(a) * r * (0.12 + (i % 5) * 0.115);
      final py = c.y + math.sin(a * 1.27) * r * (0.10 + (i % 3) * 0.16);

      final rad = 2.4 + (i % 4) * 1.8;
      final alpha = 0.05 + _foam * 0.10;

      drawCircle(
        Vector2(x: px, y: py),
        rad,
        Color.fromRGBA(bubbleCol.r, bubbleCol.g, bubbleCol.b, alpha),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Glass highlights
  // ---------------------------------------------------------------------------

  void _drawGlassHighlights(Vector2 c, double r) {
    // Reference-style diagonal reflection.
    var slant = Vector2(x: -0.38, y: 0.92);

    // During fast spin, the reflections move subtly.
    if (_state == WasherState.spin || _spinSpeed > 2.0) {
      final rot = _drumAngle * 0.12;
      final cs = math.cos(rot);
      final sn = math.sin(rot);

      slant = Vector2(
        x: slant.x * cs - slant.y * sn,
        y: slant.x * sn + slant.y * cs,
      );
    }

    final ortho = Vector2(x: -slant.y, y: slant.x);

    // Big reflection.
    final base = c + Vector2(x: -r * 0.15, y: -r * 0.02);
    final lenA = r * 0.82;
    final wA = r * 0.12;

    final a0 = base + slant * (-lenA * 0.52) + ortho * wA;
    final a1 = base + slant * (lenA * 0.48) + ortho * wA;
    final a2 = base + slant * (lenA * 0.48) - ortho * wA;
    final a3 = base + slant * (-lenA * 0.52) - ortho * wA;

    _drawQuad(a0, a1, a2, a3, highlightA);

    // Thin reflection.
    final base2 = base + Vector2(x: r * 0.30, y: -r * 0.08);
    final lenB = r * 0.48;
    final wB = r * 0.040;

    final b0 = base2 + slant * (-lenB * 0.52) + ortho * wB;
    final b1 = base2 + slant * (lenB * 0.48) + ortho * wB;
    final b2 = base2 + slant * (lenB * 0.48) - ortho * wB;
    final b3 = base2 + slant * (-lenB * 0.52) - ortho * wB;

    _drawQuad(b0, b1, b2, b3, highlightB);

    // Very subtle third glint.
    final base3 = base2 + Vector2(x: r * 0.08, y: -r * 0.015);
    final lenC = r * 0.34;
    final wC = r * 0.024;

    final c0 = base3 + slant * (-lenC * 0.52) + ortho * wC;
    final c1 = base3 + slant * (lenC * 0.48) + ortho * wC;
    final c2 = base3 + slant * (lenC * 0.48) - ortho * wC;
    final c3 = base3 + slant * (-lenC * 0.52) - ortho * wC;

    _drawQuad(c0, c1, c2, c3, highlightC);
  }

  // ---------------------------------------------------------------------------
  // Steam / mist
  // ---------------------------------------------------------------------------

  void _drawSteam(Vector2 c, double r) {
    if (_steam <= 0.01) return;

    final innerR = math.max(0.0, r - ringThickness - 8.0);
    const plumeCount = 8;

    for (int i = 0; i < plumeCount; i++) {
      final phase = _t * 1.8 + i * 0.72;
      final ring = 0.18 + (i % 5) * 0.11;
      final swirl = phase + i * 0.35;

      final x = c.x + math.cos(swirl) * innerR * ring * 0.95;
      final y =
          c.y + math.sin(swirl * 1.15) * innerR * ring * 0.72 - innerR * 0.08;

      final rx = 7.0 + (i % 4) * 1.8;
      final ry = 4.2 + (i % 3) * 1.2;

      final alpha = (0.10 + i * 0.008) * _steam;

      _drawEllipseFilledLocal(
        center: Vector2(x: x, y: y),
        rx: rx,
        ry: ry,
        color: Color.fromRGBA(steamCol.r, steamCol.g, steamCol.b, alpha),
        steps: 42,
      );

      _drawEllipseFilledLocal(
        center: Vector2(x: x + 0.4, y: y - 0.5),
        rx: rx * 0.52,
        ry: ry * 0.52,
        color: Color.fromRGBA(
          steamCoreCol.r,
          steamCoreCol.g,
          steamCoreCol.b,
          alpha * 0.55,
        ),
        steps: 32,
      );
    }

    // Base mist inside the glass.
    _drawEllipseFilledLocal(
      center: Vector2(x: c.x, y: c.y + innerR * 0.07),
      rx: innerR * 0.78,
      ry: innerR * 0.28,
      color: Color.fromRGBA(0.86, 0.93, 0.98, 0.18 * _steam),
      steps: 56,
    );
  }

  // ---------------------------------------------------------------------------
  // Rotor / spin blur
  // ---------------------------------------------------------------------------

  void _drawSpinRotor(Vector2 c, double r) {
    final speedN = (_spinSpeed / 5.2).clamp(0.0, 1.0);
    if (speedN <= 0.035) return;

    const bladeCount = 3;

    final hubR = r * (0.10 + speedN * 0.025);
    final bladeLen = r * (0.55 + speedN * 0.08);
    final w0 = r * (0.115 + speedN * 0.035);
    final w1 = r * (0.048 + speedN * 0.018);

    final bladeAlpha = 0.10 + speedN * 0.20;

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

      _drawQuad(
        p0,
        p1,
        p2,
        p3,
        Color.fromRGBA(rotorCol.r, rotorCol.g, rotorCol.b, bladeAlpha),
      );
    }

    // Central cap.
    drawCircle(
      c,
      hubR,
      Color.fromRGBA(0.86, 0.93, 0.98, 0.22 + speedN * 0.16),
    );

    // Soft blur ring in spin state.
    _drawEllipseFilledLocal(
      center: c,
      rx: r * 0.72,
      ry: r * 0.62,
      color: Color.fromRGBA(
        rotorFastCol.r,
        rotorFastCol.g,
        rotorFastCol.b,
        0.025 + speedN * 0.07,
      ),
      steps: 48,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _drawQuad(
    Vector2 p0,
    Vector2 p1,
    Vector2 p2,
    Vector2 p3,
    Color c,
  ) {
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
      final t = (i / steps) * 2.0 * math.pi;

      pts.append(Vector2(
        x: center.x + rx * math.cos(t),
        y: center.y + ry * math.sin(t),
      ));
    }

    drawColoredPolygon(pts, color);
  }
}
