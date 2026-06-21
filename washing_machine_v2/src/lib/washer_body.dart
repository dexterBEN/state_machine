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

  WasherBody.withNonNullOwner(Pointer<Void> owner)
      : super.withNonNullOwner(owner);

  // ---------------------------------------------------------------------------
  // Global shape / isometric proportions
  // ---------------------------------------------------------------------------

  /// Compact front face, close to the Dribbble reference proportions.
  final Vector2 frontSize = Vector2(x: 305, y: 300);

  /// The side face stays visible without dominating the body.
  final Vector2 depth = Vector2(x: 90, y: -32);

  /// Scene centering adjustment.
  final Vector2 sceneOffset = Vector2(x: -10, y: -24);

  /// Top control band height.
  final double topBandH = 38;

  /// Small base thickness at the bottom.
  final double baseH = 7;

  /// Gap between body and shadow.
  final double groundGap = 8;

  /// Front top edge slope.
  ///
  /// This is what makes the front face less "flat rectangle" and more
  /// pseudo-isometric.
  final double frontTopSlope = 24.0;

  /// Small lean on the right vertical front edge.
  final double frontRightLean = -6.0;

  /// Small corrections to make the back/right face feel less mechanical.
  final double backTopExtraY = 2.0;
  final double backBottomLeanX = -5.0;
  final double backBottomExtraY = -3.0;

  // ---------------------------------------------------------------------------
  // Hatch placement on the front face
  // ---------------------------------------------------------------------------

  /// Position expressed in normalized front-face coordinates.
  ///
  /// x = 0.0 left side of front face
  /// x = 1.0 right side of front face
  ///
  /// y = 0.0 top of front face
  /// y = 1.0 bottom of front face
  final double hatchX = 0.35;
  final double hatchY = 0.61;

  /// Slight rotation to align the hatch with the fake perspective.
  final double hatchTiltRad = -0.18;

  /// Scale applied to the WasherHatch child.
  ///
  /// This squashes the circular hatch into a front-face ellipse.
  final Vector2 hatchScale = Vector2(x: 0.86, y: 0.72);

  bool debugGeometry = false;

  // ---------------------------------------------------------------------------
  // Palette
  // ---------------------------------------------------------------------------

  final Color frontCol = Color.fromRGBA(0.975, 0.975, 0.988, 1.0);
  final Color frontSoftShade = Color.fromRGBA(0.82, 0.85, 0.89, 0.10);

  final Color rightColA = Color.fromRGBA(0.76, 0.79, 0.82, 1.0);
  final Color rightColB = Color.fromRGBA(0.68, 0.72, 0.76, 1.0);
  final Color rightColC = Color.fromRGBA(0.66, 0.70, 0.74, 1.0);
  final Color rightColD = Color.fromRGBA(0.76, 0.79, 0.82, 1.0);

  final Color topColA = Color.fromRGBA(0.97, 0.94, 0.99, 1.0);
  final Color topColB = Color.fromRGBA(0.995, 0.975, 1.0, 1.0);
  final Color topColC = Color.fromRGBA(0.90, 0.89, 0.96, 1.0);
  final Color topColD = Color.fromRGBA(0.96, 0.935, 0.99, 1.0);

  final Color bandFront = Color.fromRGBA(0.78, 0.75, 0.92, 1.0);
  final Color bandRight = Color.fromRGBA(0.61, 0.64, 0.82, 1.0);
  final Color bandTop = Color.fromRGBA(0.90, 0.86, 0.98, 1.0);

  final Color seamCol = Color.fromRGBA(0.98, 0.99, 1.0, 0.18);
  final Color seamStrong = Color.fromRGBA(1.0, 1.0, 1.0, 0.34);

  final Color baseSoft = Color.fromRGBA(0.76, 0.80, 0.83, 0.42);
  final Color shadowCol = Color.fromRGBA(0.14, 0.10, 0.18, 0.18);

  // ---------------------------------------------------------------------------
  // Layout points
  // ---------------------------------------------------------------------------

  late Vector2 A;
  late Vector2 B;
  late Vector2 C;
  late Vector2 D;

  late Vector2 A2;
  late Vector2 B2;
  late Vector2 C2;

  late Vector2 _lastVp;

  @override
  void vReady() {
    _computeLayout();
    queueRedraw();
  }

  @override
  void vDraw() {
    _ensureLayout();

    _drawShadow();

    // Draw order matters.
    // The right face is behind the front face.
    // The top face is drawn after both to sit visually above the cabinet.
    _drawRight();
    _drawFront();
    _drawTop();

    _drawFrontVolume();
    _drawBand();
    _drawPanelDetails();

    _drawBase();
    _drawSeams();

    if (debugGeometry) {
      _drawDebugGeometry();
    }
  }

  // ---------------------------------------------------------------------------
  // Public helpers for WasherHatch
  // ---------------------------------------------------------------------------

  Vector2 getHatchCenterWorld() {
    return frontPoint(hatchX, hatchY);
  }

  double getHatchTiltRad() => hatchTiltRad;

  Vector2 getHatchScale() => hatchScale;

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  void _computeLayout() {
    final vp = getViewportRect().size;
    _lastVp = vp;

    final totalW = frontSize.x + depth.x;
    final totalH = frontSize.y + depth.y.abs();

    final ox = (vp.x - totalW) * 0.5;
    final oy = (vp.y - totalH) * 0.5;

    A = Vector2(
      x: ox + sceneOffset.x,
      y: oy + depth.y.abs() + sceneOffset.y,
    );

    B = A + Vector2(x: frontSize.x, y: frontTopSlope);
    C = B + Vector2(x: frontRightLean, y: frontSize.y);
    D = A + Vector2(x: 0, y: frontSize.y);

    A2 = A + depth;

    B2 = B +
        Vector2(
          x: depth.x,
          y: depth.y + backTopExtraY,
        );

    C2 = C +
        Vector2(
          x: depth.x + backBottomLeanX,
          y: depth.y + backBottomExtraY,
        );
  }

  void _ensureLayout() {
    final vp = getViewportRect().size;

    final changed =
        (vp.x - _lastVp.x).abs() > 0.01 || (vp.y - _lastVp.y).abs() > 0.01;

    if (changed) {
      _computeLayout();
      queueRedraw();
    }
  }

  // ---------------------------------------------------------------------------
  // Front-face coordinate system
  // ---------------------------------------------------------------------------

  /// Converts normalized coordinates on the front face to a world/local point.
  ///
  /// x: 0.0 = left edge, 1.0 = right edge
  /// y: 0.0 = top edge,  1.0 = bottom edge
  ///
  /// This is the key helper that makes the body easier to tune.
  /// All panel details should ideally be placed with this.
  Vector2 frontPoint(double x, double y) {
    final xx = x.clamp(0.0, 1.0);
    final yy = y.clamp(0.0, 1.0);

    final left = _lerp(A, D, yy);
    final right = _lerp(B, C, yy);

    return _lerp(left, right, xx);
  }

  /// Point on the right face.
  ///
  /// verticalT:
  ///   0.0 = top edge B/B2
  ///   1.0 = bottom edge C/C2
  ///
  /// depthT:
  ///   0.0 = front edge B/C
  ///   1.0 = back edge B2/C2
  Vector2 rightFacePoint(double verticalT, double depthT) {
    final yy = verticalT.clamp(0.0, 1.0);
    final dd = depthT.clamp(0.0, 1.0);

    final frontEdge = _lerp(B, C, yy);
    final backEdge = _lerp(B2, C2, yy);

    return _lerp(frontEdge, backEdge, dd);
  }

  /// Point on the top face.
  ///
  /// xT:
  ///   0.0 = left side A/A2
  ///   1.0 = right side B/B2
  ///
  /// depthT:
  ///   0.0 = front edge A/B
  ///   1.0 = back edge A2/B2
  Vector2 topFacePoint(double xT, double depthT) {
    final xx = xT.clamp(0.0, 1.0);
    final dd = depthT.clamp(0.0, 1.0);

    final frontEdge = _lerp(A, B, xx);
    final backEdge = _lerp(A2, B2, xx);

    return _lerp(frontEdge, backEdge, dd);
  }

  // ---------------------------------------------------------------------------
  // Main parts
  // ---------------------------------------------------------------------------

  void _drawShadow() {
    final center = Vector2(
      x: (D.x + C2.x) * 0.5 + 10,
      y: math.max(C.y, C2.y) + groundGap + 4,
    );

    _drawEllipse(
      center,
      132,
      13,
      shadowCol,
    );

    _drawEllipse(
      center + Vector2(x: 34, y: -2),
      84,
      8,
      Color.fromRGBA(0.10, 0.07, 0.13, 0.07),
    );
  }

  void _drawRight() {
    _drawQuadGradient(
      B2,
      C2,
      C,
      B,
      rightColA,
      rightColB,
      rightColC,
      rightColD,
    );

    // Soft vertical shade inside the right face.
    _drawQuad(
      rightFacePoint(0.16, 0.78),
      rightFacePoint(0.76, 0.78),
      rightFacePoint(0.82, 0.92),
      rightFacePoint(0.22, 0.92),
      Color.fromRGBA(0.35, 0.38, 0.45, 0.025),
    );

    // Slight front edge light on the side.
    drawLine(
      B + Vector2(x: -0.5, y: 2),
      C + Vector2(x: -0.5, y: -2),
      Color.fromRGBA(1.0, 1.0, 1.0, 0.10),
      width: 1.2,
      antialiased: true,
    );
  }

  void _drawFront() {
    _drawQuad(A, B, C, D, frontCol);
  }

  void _drawTop() {
    _drawQuadGradient(
      A2,
      B2,
      B,
      A,
      topColA,
      topColB,
      topColC,
      topColD,
    );

    // Top front highlight edge.
    drawLine(
      A + Vector2(x: 5, y: 1.0),
      B + Vector2(x: -7, y: 1.0),
      Color.fromRGBA(1.0, 1.0, 1.0, 0.46),
      width: 2.0,
      antialiased: true,
    );

    // Top rear subtle darker edge.
    drawLine(
      A2 + Vector2(x: 4, y: 1),
      B2 + Vector2(x: -4, y: 1),
      Color.fromRGBA(0.68, 0.65, 0.82, 0.11),
      width: 1.2,
      antialiased: true,
    );

    // Very soft top sheen.
    _drawQuad(
      topFacePoint(0.05, 0.15),
      topFacePoint(0.94, 0.15),
      topFacePoint(0.88, 0.25),
      topFacePoint(0.10, 0.25),
      Color.fromRGBA(1.0, 1.0, 1.0, 0.10),
    );
  }

  void _drawFrontVolume() {
    // Right vertical highlight on front face.
    _drawQuad(
      frontPoint(0.975, 0.03),
      frontPoint(1.0, 0.00),
      frontPoint(1.0, 0.98),
      frontPoint(0.975, 0.96),
      Color.fromRGBA(1.0, 1.0, 1.0, 0.075),
    );

    // Bottom front shade.
    _drawQuad(
      frontPoint(0.00, 0.965),
      frontPoint(1.00, 0.965),
      C,
      D,
      frontSoftShade,
    );

    // Left soft shade to avoid an overly flat front face.
    _drawQuad(
      A,
      frontPoint(0.055, 0.00),
      frontPoint(0.055, 0.96),
      D,
      Color.fromRGBA(0.80, 0.84, 0.88, 0.055),
    );
  }

  void _drawBand() {
    final t = (topBandH / frontSize.y).clamp(0.0, 1.0);

    final fL = frontPoint(0.0, t);
    final fR = frontPoint(1.0, t);
    final rB = rightFacePoint(t, 1.0);

    // Main purple front band.
    _drawQuad(A, B, fR, fL, bandFront);

    // Right band.
    _drawQuad(B2, rB, fR, B, bandRight);

    // Small cap on the top surface.
    _drawQuad(
      topFacePoint(0.00, 0.13),
      topFacePoint(1.00, 0.13),
      topFacePoint(1.00, 0.27),
      topFacePoint(0.00, 0.27),
      bandTop,
    );

    // Band lower highlight.
    drawLine(
      fL + Vector2(x: 1, y: 0.5),
      fR + Vector2(x: -2, y: 0.5),
      Color.fromRGBA(1.0, 1.0, 1.0, 0.22),
      width: 1.2,
      antialiased: true,
    );

    drawLine(
      fL + Vector2(x: 1, y: 2.0),
      fR + Vector2(x: -2, y: 2.0),
      Color.fromRGBA(0.55, 0.50, 0.70, 0.08),
      width: 2.0,
      antialiased: true,
    );
  }

  void _drawPanelDetails() {
    final t = (topBandH / frontSize.y).clamp(0.0, 1.0);

    // Details are now positioned inside the band using normalized front coords,
    // instead of interpolating only on the lower band edge.
    final detailY = t * 0.54;

    // Knob.
    final knobC = frontPoint(0.43, detailY);

    drawCircle(
      knobC + Vector2(x: 0.8, y: 1.1),
      12.8,
      Color.fromRGBA(0.58, 0.55, 0.76, 0.13),
    );

    drawCircle(
      knobC,
      12.4,
      Color.fromRGBA(0.96, 0.96, 0.985, 1.0),
    );

    drawCircle(
      knobC + Vector2(x: 0.7, y: 0.7),
      11.4,
      Color.fromRGBA(0.89, 0.90, 0.94, 1.0),
    );

    drawLine(
      knobC + Vector2(x: -2.0, y: -1.0),
      knobC + Vector2(x: 4.8, y: 2.8),
      Color.fromRGBA(0.62, 0.62, 0.70, 0.82),
      width: 2.0,
      antialiased: true,
    );

    // Display panel.
    final panelW = 56.0;
    final panelH = 28.0;
    final panelC = frontPoint(0.67, detailY);

    _drawRoundedRect(
      center: panelC + Vector2(x: 1.2, y: 1.4),
      width: panelW,
      height: panelH,
      radius: 9.5,
      color: Color.fromRGBA(0.52, 0.50, 0.72, 0.12),
    );

    _drawRoundedRect(
      center: panelC,
      width: panelW,
      height: panelH,
      radius: 9.5,
      color: Color.fromRGBA(0.91, 0.91, 0.94, 1.0),
    );

    _drawRoundedRect(
      center: panelC + Vector2(x: -1.0, y: -1.0),
      width: panelW - 3.0,
      height: panelH - 3.0,
      radius: 8.5,
      color: Color.fromRGBA(0.985, 0.985, 1.0, 1.0),
    );
  }

  void _drawBase() {
    _drawQuad(
      frontPoint(0.025, 0.98),
      frontPoint(0.975, 0.98),
      C,
      D,
      baseSoft,
    );

    drawLine(
      D + Vector2(x: 6, y: -1),
      C + Vector2(x: -8, y: -1),
      Color.fromRGBA(0.68, 0.73, 0.76, 0.20),
      width: 1.2,
      antialiased: true,
    );
  }

  void _drawSeams() {
    final t = (topBandH / frontSize.y).clamp(0.0, 1.0);

    final fL = frontPoint(0.0, t);
    final fR = frontPoint(1.0, t);
    final rB = rightFacePoint(t, 1.0);

    // Top/front edges.
    drawLine(A, B, seamCol, width: 1.2, antialiased: true);

    drawLine(
      A2,
      B2,
      Color.fromRGBA(0.95, 0.95, 1.0, 0.18),
      width: 1.0,
      antialiased: true,
    );

    drawLine(B2, B, seamCol, width: 1.0, antialiased: true);

    drawLine(
      B2,
      C2,
      Color.fromRGBA(0.88, 0.90, 0.96, 0.20),
      width: 1.0,
      antialiased: true,
    );

    drawLine(
      C2,
      C,
      Color.fromRGBA(0.82, 0.86, 0.90, 0.16),
      width: 1.0,
      antialiased: true,
    );

    // Front/right edge.
    drawLine(B, C, seamStrong, width: 1.3, antialiased: true);

    // Band separation.
    drawLine(
      fL,
      fR,
      Color.fromRGBA(0.96, 0.97, 0.99, 0.16),
      width: 1.0,
      antialiased: true,
    );

    drawLine(
      rB,
      fR,
      Color.fromRGBA(0.86, 0.87, 0.95, 0.11),
      width: 0.9,
      antialiased: true,
    );

    // Bottom front edge.
    drawLine(
      D,
      C,
      Color.fromRGBA(0.72, 0.76, 0.78, 0.18),
      width: 1.0,
      antialiased: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Debug geometry
  // ---------------------------------------------------------------------------

  void _drawDebugGeometry() {
    final frontEdge = Color.fromRGBA(1.0, 0.18, 0.22, 0.95);
    final sideEdge = Color.fromRGBA(0.22, 0.66, 1.0, 0.95);
    final topEdge = Color.fromRGBA(1.0, 0.84, 0.12, 0.95);
    final depthEdge = Color.fromRGBA(0.0, 0.90, 0.78, 0.95);
    final frontPointCol = Color.fromRGBA(1.0, 0.08, 0.12, 1.0);
    final backPointCol = Color.fromRGBA(0.0, 0.92, 1.0, 1.0);

    // Front face A-B-C-D.
    drawLine(A, B, frontEdge, width: 2.5, antialiased: true);
    drawLine(B, C, frontEdge, width: 2.5, antialiased: true);
    drawLine(C, D, frontEdge, width: 2.5, antialiased: true);
    drawLine(D, A, frontEdge, width: 2.5, antialiased: true);

    // Top face A-A2-B2-B.
    drawLine(A, A2, depthEdge, width: 2.5, antialiased: true);
    drawLine(A2, B2, topEdge, width: 2.5, antialiased: true);
    drawLine(B2, B, depthEdge, width: 2.5, antialiased: true);

    // Right side B-B2-C2-C.
    drawLine(B, B2, sideEdge, width: 2.5, antialiased: true);
    drawLine(B2, C2, sideEdge, width: 2.5, antialiased: true);
    drawLine(C2, C, sideEdge, width: 2.5, antialiased: true);
    drawLine(C, B, sideEdge, width: 2.5, antialiased: true);

    _drawDebugPoint(A, frontPointCol);
    _drawDebugPoint(B, frontPointCol);
    _drawDebugPoint(C, frontPointCol);
    _drawDebugPoint(D, frontPointCol);

    _drawDebugPoint(A2, backPointCol);
    _drawDebugPoint(B2, backPointCol);
    _drawDebugPoint(C2, backPointCol);
  }

  void _drawDebugPoint(Vector2 p, Color color) {
    drawCircle(p, 5.0, Color.fromRGBA(0.02, 0.02, 0.03, 0.90));
    drawCircle(p, 3.5, color);
  }

  // ---------------------------------------------------------------------------
  // Geometry helpers
  // ---------------------------------------------------------------------------

  Vector2 _lerp(Vector2 a, Vector2 b, double t) {
    return Vector2(
      x: a.x + (b.x - a.x) * t,
      y: a.y + (b.y - a.y) * t,
    );
  }

  void _drawQuad(Vector2 p0, Vector2 p1, Vector2 p2, Vector2 p3, Color c) {
    final pts = PackedVector2Array();
    pts.append(p0);
    pts.append(p1);
    pts.append(p2);
    pts.append(p3);

    drawColoredPolygon(pts, c);
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

        pts.append(Vector2(
          x: cc.x + r * math.cos(t),
          y: cc.y + r * math.sin(t),
        ));
      }
    }

    arc(cTR, -math.pi * 0.5, 0.0);
    arc(cBR, 0.0, math.pi * 0.5);
    arc(cBL, math.pi * 0.5, math.pi);
    arc(cTL, math.pi, math.pi * 1.5);

    drawColoredPolygon(pts, color);
  }
}
