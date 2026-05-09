
import 'dart:ffi';
import 'dart:math' as math;
import 'package:godot_dart/godot_dart.dart';

part 'washer_body.g.dart';

@GodotScript()
class WasherBody extends Node2D {
  @override
  late final ExtensionTypeInfo<WasherBody> typeInfo = WasherBody.sTypeInfo;

  @pragma('vm:entry-point')
  static final ExtensionTypeInfo<WasherBody> sTypeInfo = _$WasherBodyTypeInfo();

  WasherBody() : super();
  WasherBody.withNonNullOwner(Pointer<Void> owner) : super.withNonNullOwner(owner);

  final Vector2 frontSize = Vector2(x: 360, y: 320);
  final Vector2 depth = Vector2(x: 128, y: -44);
  final Vector2 sceneOffset = Vector2(x: -18, y: -10);

  final double topBandH = 38;
  final double baseH = 7;
  final double groundGap = 12;

  final double hatchX = 0.39;
  final double hatchY = 0.59;
  final double hatchTiltRad = -0.22;
  final Vector2 hatchScale = Vector2(x: 1.0, y: 0.82);

  final Color frontCol = Color.fromRGBA(0.93, 0.93, 0.94, 1.0);
  final Color rightCol = Color.fromRGBA(0.69, 0.71, 0.74, 1.0);
  final Color topCol = Color.fromRGBA(0.91, 0.90, 0.94, 1.0);

  final Color bandFront = Color.fromRGBA(0.74, 0.73, 0.86, 1.0);
  final Color bandRight = Color.fromRGBA(0.59, 0.60, 0.76, 1.0);
  final Color bandTop = Color.fromRGBA(0.84, 0.83, 0.92, 1.0);

  final Color seamCol = Color.fromRGBA(0.98, 0.99, 0.99, 0.12);
  final Color baseSoft = Color.fromRGBA(0.80, 0.84, 0.88, 0.36);
  final Color shadow = Color.fromRGBA(0.17, 0.13, 0.21, 0.08);

  late Vector2 A, B, C, D;
  late Vector2 A2, B2, C2;
  late Vector2 _lastVp;

  @override
  void vReady() {
    _computeLayout();
    queueRedraw();
  }

  void _computeLayout() {
    final vp = getViewportRect().size;
    _lastVp = vp;

    final ox = (vp.x - (frontSize.x + depth.x)) * 0.5;
    final oy = (vp.y - (frontSize.y + depth.y.abs())) * 0.5;

    A = Vector2(x: ox + sceneOffset.x, y: oy + depth.y.abs() + sceneOffset.y);
    B = A + Vector2(x: frontSize.x, y: 6);
    C = B + Vector2(x: 0, y: frontSize.y);
    D = A + Vector2(x: 0, y: frontSize.y);

    A2 = A + depth;
    B2 = B + depth;
    C2 = C + depth;
  }

  Vector2 getHatchCenterWorld() {
    final hx = frontSize.x * hatchX;
    final hy = topBandH + (frontSize.y - topBandH) * hatchY;
    return Vector2(x: A.x + hx, y: A.y + hy);
  }

  double getHatchTiltRad() => hatchTiltRad;
  Vector2 getHatchScale() => hatchScale;

  @override
  void vDraw() {
    _ensureLayout();
    _drawShadow();
    _drawTop();
    _drawRight();
    _drawFront();
    _drawFrontVolume();
    _drawBand();
    _drawPanelDetails();
    _drawBase();
    _drawSeams();
  }

  void _drawShadow() {
    _drawQuad(
      Vector2(x: C.x - 2, y: C.y + 1),
      Vector2(x: C2.x + 8, y: C2.y + 4),
      Vector2(x: C2.x + 22, y: C2.y + 10),
      Vector2(x: C.x + 12, y: C.y + 13),
      Color.fromRGBA(0.16, 0.12, 0.20, 0.14),
    );
    _drawEllipse(
      Vector2(x: (D.x + C2.x) * 0.5 + 14, y: C.y + groundGap + 1),
      128,
      10,
      shadow,
    );
  }

  void _drawTop() => _drawQuadGradient(
        A2, B2, B, A,
        Color.fromRGBA(0.92, 0.91, 0.95, 1.0),
        Color.fromRGBA(0.94, 0.93, 0.96, 1.0),
        Color.fromRGBA(0.89, 0.88, 0.92, 1.0),
        Color.fromRGBA(0.90, 0.89, 0.93, 1.0),
      );

  void _drawFront() => _drawQuad(A, B, C, D, frontCol);

  void _drawRight() => _drawQuadGradient(
        B2, C2, C, B,
        Color.fromRGBA(0.72, 0.74, 0.78, 1.0),
        Color.fromRGBA(0.66, 0.68, 0.72, 1.0),
        Color.fromRGBA(0.64, 0.66, 0.70, 1.0),
        Color.fromRGBA(0.70, 0.72, 0.76, 1.0),
      );

  void _drawBand() {
    final t = (topBandH / frontSize.y).clamp(0.0, 1.0);

    final fL = _lerp(A, D, t);
    final fR = _lerp(B, C, t);
    final rF = _lerp(B, C, t);
    final rB = _lerp(B2, C2, t);

    _drawQuad(A, B, fR, fL, bandFront);
    _drawQuad(B2, rB, rF, B, bandRight);

    final tCap0 = 0.16;
    final tCap1 = 0.29;
    _drawQuad(
      _lerp(A2, A, tCap0),
      _lerp(B2, B, tCap0),
      _lerp(B2, B, tCap1),
      _lerp(A2, A, tCap1),
      bandTop,
    );
  }

  void _drawQuadGradient(
    Vector2 p0,
    Vector2 p1,
    Vector2 p2,
    Vector2 p3,
    Color c0,
    Color c1,
    Color c2,
    Color c3,
  ) {
    final pts = PackedVector2Array();
    pts.append(p0);
    pts.append(p1);
    pts.append(p2);
    pts.append(p3);

    final cols = PackedColorArray();
    cols.append(c0);
    cols.append(c1);
    cols.append(c2);
    cols.append(c3);

    drawPolygon(pts, cols);
  }

  void _drawBase() {
    _drawQuad(
      Vector2(x: D.x + 10, y: D.y - baseH),
      Vector2(x: C.x - 10, y: C.y - baseH),
      C,
      D,
      baseSoft,
    );
  }

  void _drawFrontVolume() {
    final frontHighlightW = 6.0;
    _drawQuad(
      Vector2(x: B.x - frontHighlightW, y: A.y),
      B,
      C,
      Vector2(x: C.x - frontHighlightW, y: C.y),
      Color.fromRGBA(0.98, 0.99, 1.0, 0.08),
    );

    _drawQuad(
      D,
      C,
      Vector2(x: C.x - 12, y: C.y - 1.3),
      Vector2(x: D.x + 12, y: D.y - 1.3),
      Color.fromRGBA(0.86, 0.89, 0.92, 0.08),
    );
  }

  void _drawPanelDetails() {
    final t = (topBandH / frontSize.y).clamp(0.0, 1.0);
    final fL = _lerp(A, D, t);
    final fR = _lerp(B, C, t);

    final knobC = Vector2(
      x: fL.x + (fR.x - fL.x) * 0.41,
      y: fL.y + (fR.y - fL.y) * 0.56,
    );
    drawCircle(knobC + Vector2(x: 0.8, y: 1.0), 14, Color.fromRGBA(0.68, 0.67, 0.79, 0.16));
    drawCircle(knobC, 14, Color.fromRGBA(0.93, 0.93, 0.95, 1.0));
    drawCircle(knobC + Vector2(x: 0.7, y: 0.7), 13, Color.fromRGBA(0.88, 0.89, 0.92, 1.0));
    drawLine(
      knobC + Vector2(x: -2, y: -1),
      knobC + Vector2(x: 5, y: 3),
      Color.fromRGBA(0.64, 0.64, 0.70, 0.80),
      width: 2.0,
      antialiased: true,
    );

    final panelW = 68.0;
    final panelH = 36.0;
    final panelC = Vector2(
      x: fL.x + (fR.x - fL.x) * 0.66,
      y: fL.y + (fR.y - fL.y) * 0.56,
    );
    _drawRoundedRect(
      center: panelC + Vector2(x: 1.2, y: 1.4),
      width: panelW,
      height: panelH,
      radius: 10.0,
      color: Color.fromRGBA(0.66, 0.65, 0.77, 0.12),
    );
    _drawRoundedRect(
      center: panelC,
      width: panelW,
      height: panelH,
      radius: 10.0,
      color: Color.fromRGBA(0.89, 0.90, 0.92, 1.0),
    );
    _drawRoundedRect(
      center: panelC + Vector2(x: -1.0, y: -1.0),
      width: panelW - 2.0,
      height: panelH - 2.0,
      radius: 9.0,
      color: Color.fromRGBA(0.93, 0.93, 0.95, 1.0),
    );
  }

  void _drawSeams() {
    final t = (topBandH / frontSize.y).clamp(0.0, 1.0);
    final fL = _lerp(A, D, t);
    final fR = _lerp(B, C, t);
    final rB = _lerp(B2, C2, t);

    drawLine(A, B, seamCol, width: 1.2, antialiased: true);
    drawLine(B2, B, seamCol, width: 1.0, antialiased: true);
    drawLine(B, C, Color.fromRGBA(0.98, 0.99, 1.0, 0.26), width: 1.3, antialiased: true);

    drawLine(fL, fR, Color.fromRGBA(0.96, 0.97, 0.99, 0.12), width: 1.0, antialiased: true);
    drawLine(rB, fR, Color.fromRGBA(0.86, 0.87, 0.95, 0.09), width: 0.8, antialiased: true);
  }

  void _ensureLayout() {
    final vp = getViewportRect().size;
    final changed = (vp.x - _lastVp.x).abs() > 0.01 || (vp.y - _lastVp.y).abs() > 0.01;
    if (changed) {
      _computeLayout();
      queueRedraw();
    }
  }

  Vector2 _lerp(Vector2 a, Vector2 b, double t) {
    return Vector2(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t);
  }

  void _drawQuad(Vector2 p0, Vector2 p1, Vector2 p2, Vector2 p3, Color c) {
    final pts = PackedVector2Array();
    pts.append(p0);
    pts.append(p1);
    pts.append(p2);
    pts.append(p3);
    drawColoredPolygon(pts, c);
  }

  void _drawEllipse(Vector2 c, double rx, double ry, Color col) {
    const steps = 72;
    final pts = PackedVector2Array();
    for (int i = 0; i < steps; i++) {
      final t = (i / steps) * 2 * math.pi;
      pts.append(Vector2(x: c.x + rx * math.cos(t), y: c.y + ry * math.sin(t)));
    }
    drawColoredPolygon(pts, col);
  }

  void _drawRoundedRect({
    required Vector2 center,
    required double width,
    required double height,
    required double radius,
    required Color color,
  }) {
    const cornerSteps = 10;
    final r = radius.clamp(1.0, math.min(width, height) * 0.5);
    final hw = width * 0.5;
    final hh = height * 0.5;

    final cTL = Vector2(x: center.x - hw + r, y: center.y - hh + r);
    final cTR = Vector2(x: center.x + hw - r, y: center.y - hh + r);
    final cBR = Vector2(x: center.x + hw - r, y: center.y + hh - r);
    final cBL = Vector2(x: center.x - hw + r, y: center.y + hh - r);

    final pts = PackedVector2Array();
    void arc(Vector2 cc, double a0, double a1) {
      for (int i = 0; i <= cornerSteps; i++) {
        final t = a0 + (a1 - a0) * (i / cornerSteps);
        pts.append(Vector2(x: cc.x + r * math.cos(t), y: cc.y + r * math.sin(t)));
      }
    }

    arc(cTR, -math.pi * 0.5, 0.0);
    arc(cBR, 0.0, math.pi * 0.5);
    arc(cBL, math.pi * 0.5, math.pi);
    arc(cTL, math.pi, math.pi * 1.5);
    drawColoredPolygon(pts, color);
  }
}
