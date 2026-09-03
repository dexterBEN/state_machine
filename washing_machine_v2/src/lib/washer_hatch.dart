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
  double outerRadius = 78.0;

  /// Slightly thinner ring for a softer pastel contour.
  double ringThickness = 10.5;

  /// Local geometric tilt applied to the hatch polygons.
  ///
  /// WasherBody still controls the global placement/scale. This angle only
  /// gives the hatch layers a cleaner pseudo-isometric construction.
  double hatchGeometryAngleRad = -0.30;

  /// Keeps the glass slightly inset from the rim.
  double glassInset = 5.0;

  // ---------------------------------------------------------------------------
  // Palette
  // ---------------------------------------------------------------------------

  // Pastel rim colors.
  final Color rimShadow = Color.fromRGBA(0.38, 0.30, 0.52, 0.075);
  final Color rimOuter = Color.fromRGBA(0.78, 0.71, 0.97, 1.0);
  final Color rimInner = Color.fromRGBA(0.61, 0.55, 0.80, 1.0);
  final Color rimInnerLight = Color.fromRGBA(0.82, 0.78, 0.93, 1.0);

  // Glass colors.
  final Color glassBase = Color.fromRGBA(0.57, 0.70, 0.81, 0.90);
  final Color glassWash = Color.fromRGBA(0.90, 0.96, 1.0, 0.16);

  // Highlights.
  final Color highlightA = Color.fromRGBA(0.96, 0.99, 1.0, 0.44);
  final Color highlightB = Color.fromRGBA(0.98, 0.995, 1.0, 0.28);

  // Liquids / bubbles.
  final Color waterTop = Color.fromRGBA(0.64, 0.80, 0.92, 0.30);
  final Color waterBottom = Color.fromRGBA(0.42, 0.63, 0.80, 0.52);
  final Color bubbleCol = Color.fromRGBA(0.96, 0.99, 1.0, 0.16);

  // Rotor / spin blur.
  final Color rotorCol = Color.fromRGBA(0.77, 0.87, 0.97, 0.28);
  final Color rotorFastCol = Color.fromRGBA(0.84, 0.92, 0.99, 0.18);

  // Steam / mist.
  final Color steamCol = Color.fromRGBA(0.90, 0.96, 0.99, 0.14);

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

  bool debugWaterShaderMagenta = false;
  bool debugWaterShaderExaggerated = false;

  Polygon2D? _waterLayer;
  ShaderMaterial? _waterMaterial;
  Node2D? _hatchOverlay;
  Polygon2D? _glassVeilLayer;
  Polygon2D? _highlightALayer;
  Polygon2D? _highlightBLayer;
  bool _waterShaderLoaded = false;
  bool _waterShaderReadyLogged = false;
  bool _waterUvLogged = false;
  ImageTexture? _waterUvTexture;

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
        _targetWaterLevel = 0.50;
        _targetFoam = 0.32;
        _targetSpinSpeed = 0.85;
        _targetSteam = 0.0;
        break;

      case WasherState.rinse:
        _targetWaterLevel = 0.54;
        _targetFoam = 0.12;
        _targetSpinSpeed = 0.95;
        _targetSteam = 0.20;
        break;

      case WasherState.spin:
        _targetWaterLevel = 0.04;
        _targetFoam = 0.0;
        _targetSpinSpeed = 3.6;
        _targetSteam = 0.0;
        break;

      case WasherState.done:
        _targetWaterLevel = 0.0;
        _targetFoam = 0.0;
        _targetSpinSpeed = 0.0;
        _targetSteam = 0.0;
        break;
    }

    _updateWaterShaderUniforms();
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
    _setupWaterLayer();
    _setupHatchOverlay();
    _rebuildLayerGeometry();
    _updateWaterShaderUniforms();
    _syncLayerVisibility();
    _logWaterShaderReady();

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

    _updateWaterShaderUniforms();
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
    final rimRy = outerRadius * 0.90;
    final innerRy = innerR * 0.90;
    final glassRy = glassR * 0.82;
    final tilt = hatchGeometryAngleRad;

    // Soft cast shadow behind the door.
    _drawEllipseFilledLocal(
      center: Vector2(x: 3.6, y: 4.2),
      rx: outerRadius * 0.98,
      ry: rimRy * 0.96,
      color: rimShadow,
      steps: 72,
      rotation: tilt,
    );

    // Simple rim stack: outer lavender, light inner ring, thin glass seat.
    _drawEllipseFilledLocal(
      center: c + Vector2(x: 0.8, y: 1.2),
      rx: outerRadius,
      ry: rimRy,
      color: rimOuter,
      steps: 80,
      rotation: tilt,
    );
    _drawEllipseFilledLocal(
      center: c + Vector2(x: -0.4, y: -0.6),
      rx: innerR + 0.8,
      ry: innerRy + 0.6,
      color: rimInnerLight,
      steps: 80,
      rotation: tilt,
    );
    _drawEllipseFilledLocal(
      center: c + Vector2(x: 0.3, y: 0.3),
      rx: glassR + 2.6,
      ry: glassRy + 2.2,
      color: rimInner,
      steps: 80,
      rotation: tilt,
    );

    // Glass base.
    _drawEllipseFilledLocal(
      center: c + Vector2(x: -1.2, y: -0.6),
      rx: glassR * 0.98,
      ry: glassRy,
      color: glassBase,
      steps: 80,
      rotation: tilt,
    );

    // Simple asymmetric depth shape behind the glass.
    _drawQuad(
      _rotatePoint(
        c + Vector2(x: -glassR * 0.76, y: -glassRy * 0.44),
        tilt,
        origin: c,
      ),
      _rotatePoint(
        c + Vector2(x: -glassR * 0.18, y: -glassRy * 0.62),
        tilt,
        origin: c,
      ),
      _rotatePoint(
        c + Vector2(x: glassR * 0.08, y: glassRy * 0.34),
        tilt,
        origin: c,
      ),
      _rotatePoint(
        c + Vector2(x: -glassR * 0.58, y: glassRy * 0.52),
        tilt,
        origin: c,
      ),
      Color.fromRGBA(0.24, 0.34, 0.46, 0.12),
    );

    _syncLayerVisibility();

    // Bubbles are drawn before the shader water layer.
    _drawBubbles(c, glassR - 10.0);

    // Rotor stays behind the shader water layer, glass veil, and static highlights.
    _drawSpinRotor(c, glassR - 6.0);

    // Steam / mist.
    _drawSteam(c, outerRadius);
  }

  void _setupWaterLayer() {
    if (_waterLayer != null) return;

    final layer = Polygon2D();
    layer.setName('WaterLayer');
    layer.setZIndex(1);
    layer.setColor(Color.fromRGBA(1.0, 1.0, 1.0, 1.0));
    _waterUvTexture = _createWhiteUvTexture();
    layer.setTexture(_waterUvTexture);

    final material = ShaderMaterial();
    final shader = ResourceLoader.singleton.load(
      'res://src/hatch_water.gdshader',
      typeHint: 'Shader',
    );

    if (shader is Shader) {
      material.setShader(shader);
      layer.setMaterial(material);
      _waterMaterial = material;
      _waterShaderLoaded = true;
    }

    _waterLayer = layer;
    addChild(layer);
  }

  void _setupHatchOverlay() {
    if (_hatchOverlay != null) return;

    final overlay = Node2D();
    overlay.setName('HatchOverlay');
    overlay.setZIndex(2);

    _glassVeilLayer = _makeOverlayPolygon(
      'GlassVeil',
      Color.fromRGBA(glassWash.r, glassWash.g, glassWash.b, 0.10),
    );
    _highlightALayer = _makeOverlayPolygon('GlassHighlightMain', highlightA);
    _highlightBLayer =
        _makeOverlayPolygon('GlassHighlightSecondary', highlightB);

    overlay.addChild(_glassVeilLayer);
    overlay.addChild(_highlightALayer);
    overlay.addChild(_highlightBLayer);

    _hatchOverlay = overlay;
    addChild(overlay);
  }

  Polygon2D _makeOverlayPolygon(String name, Color color) {
    final layer = Polygon2D();
    layer.setName(name);
    layer.setColor(color);
    return layer;
  }

  ImageTexture? _createWhiteUvTexture() {
    final image = Image.create(1, 1, false, ImageFormat.rgba8);
    if (image == null) return null;

    image.fill(Color.fromRGBA(1.0, 1.0, 1.0, 1.0));
    return ImageTexture.createFromImage(image);
  }

  void _rebuildLayerGeometry() {
    final c = Vector2(x: 0, y: 0);
    final innerR = math.max(0.0, outerRadius - ringThickness);
    final glassR = math.max(0.0, innerR - glassInset);
    final glassRy = glassR * 0.82;
    final tilt = hatchGeometryAngleRad;

    _waterLayer?.setPolygon(_ellipsePolygon(
      center: c + Vector2(x: -1.2, y: -0.6),
      rx: glassR * 0.98,
      ry: glassRy,
      steps: 64,
      rotation: tilt,
      rotationOrigin: c,
    ));
    final waterUv = _ellipseUv(steps: 64);
    _waterLayer?.setUv(waterUv);
    _logWaterUv(waterUv);

    _glassVeilLayer?.setPolygon(_ellipsePolygon(
      center: c + Vector2(x: -1.8, y: -2.0),
      rx: glassR - 5.5,
      ry: glassRy - 3.0,
      steps: 72,
      rotation: tilt,
      rotationOrigin: c,
    ));

    final highlights = _glassHighlightPolygons(c, glassR, tilt);
    _highlightALayer?.setPolygon(highlights.$1);
    _highlightBLayer?.setPolygon(highlights.$2);
  }

  void _syncLayerVisibility() {
    _waterLayer?.setVisible(
      debugWaterShaderMagenta ||
          debugWaterShaderExaggerated ||
          _waterShaderFillLevel() > 0.001,
    );
    _hatchOverlay?.setVisible(true);
  }

  void _updateWaterShaderUniforms() {
    final material = _waterMaterial;
    if (material == null) return;

    final level = _waterShaderFillLevel();
    final amplitude = _waterShaderWaveAmplitude();
    final frequency = _waterShaderWaveFrequency();
    final speed = _waterShaderWaveSpeed();

    material.setShaderParameter(
      'debug_magenta',
      Variant(debugWaterShaderMagenta),
    );
    material.setShaderParameter(
      'debug_exaggerated',
      Variant(debugWaterShaderExaggerated),
    );
    material.setShaderParameter('fill_level', Variant(level));
    material.setShaderParameter('wave_amplitude', Variant(amplitude));
    material.setShaderParameter('wave_frequency', Variant(frequency));
    material.setShaderParameter('wave_speed', Variant(speed));
  }

  double _waterShaderFillLevel() {
    return _waterLevel.clamp(0.0, 1.0).toDouble();
  }

  double _waterShaderWaveAmplitude() {
    final isWash = _state == WasherState.wash;
    final isRinse = _state == WasherState.rinse;
    final isSpin = _state == WasherState.spin;

    return isWash
        ? 0.04
        : isRinse
            ? 0.026
            : isSpin
                ? 0.012
                : 0.006;
  }

  double _waterShaderWaveFrequency() {
    return _state == WasherState.wash ? 15.0 : 11.0;
  }

  double _waterShaderWaveSpeed() {
    final isWash = _state == WasherState.wash;
    final isRinse = _state == WasherState.rinse;
    final isSpin = _state == WasherState.spin;

    return isWash
        ? 2.5
        : isRinse
            ? 2.0
            : isSpin
                ? 3.0
                : 0.7;
  }

  void _logWaterShaderReady() {
    if (_waterShaderReadyLogged) return;
    _waterShaderReadyLogged = true;

    print('[WaterShader] WaterLayer ready');
    print('[WaterShader] shader=res://src/hatch_water.gdshader');
    print('[WaterShader] ShaderMaterial attached=$_waterShaderLoaded');
    print('[WaterShader] WaterLayer exists=${_waterLayer != null}');
    print('[WaterShader] WaterLayer visible=${_waterLayer?.isVisible()}');
    print('[WaterShader] WaterLayer z_index=${_waterLayer?.getZIndex()}');
    print(
        '[WaterShader] WaterLayer vertices=${_waterLayer?.getPolygon().size()}');
    print('[WaterShader] WaterLayer uvs=${_waterLayer?.getUv().size()}');
    print('[WaterShader] WaterLayer color.a=${_waterLayer?.getColor().a}');
    print(
        '[WaterShader] WaterLayer modulate.a=${_waterLayer?.getModulate().a}');
    print('[WaterShader] WaterLayer material=${_waterLayer?.getMaterial()}');
    print('[WaterShader] Material shader=${_waterMaterial?.getShader()}');
    print(
        '[WaterShader] Material shader path=${_waterMaterial?.getShader()?.getPath()}');
    print(
        '[WaterShader] WaterLayer texture != null=${_waterLayer?.getTexture() != null}');
    print(
      '[WaterShader] texture size='
      '${_waterLayer?.getTexture()?.getWidth()}x'
      '${_waterLayer?.getTexture()?.getHeight()}',
    );
    print('[WaterShader] uv count=${_waterLayer?.getUv().size()}');
    print(
      '[WaterShader] uniforms '
      'debug_magenta=$debugWaterShaderMagenta '
      'debug_exaggerated=$debugWaterShaderExaggerated '
      'fill_level=${_waterShaderFillLevel()} '
      'wave_amplitude=${_waterShaderWaveAmplitude()} '
      'wave_frequency=${_waterShaderWaveFrequency()} '
      'wave_speed=${_waterShaderWaveSpeed()}',
    );
    print(
      '[WaterShader] exaggerated=$debugWaterShaderExaggerated '
      'fill_level=${_waterShaderFillLevel()} '
      'wave_amplitude=${_waterShaderWaveAmplitude()} '
      'wave_frequency=${_waterShaderWaveFrequency()} '
      'wave_speed=${_waterShaderWaveSpeed()}',
    );
  }

  void _logWaterUv(PackedVector2Array uv) {
    if (_waterUvLogged) return;
    _waterUvLogged = true;

    if (uv.size() == 0) {
      print('[WaterShader][UV] count=0');
      return;
    }

    var minU = uv[0].x;
    var maxU = uv[0].x;
    var minV = uv[0].y;
    var maxV = uv[0].y;

    for (int i = 1; i < uv.size(); i++) {
      final p = uv[i];
      minU = math.min(minU, p.x);
      maxU = math.max(maxU, p.x);
      minV = math.min(minV, p.y);
      maxV = math.max(maxV, p.y);
    }

    print('[WaterShader][UV] count=${uv.size()}');
    print('[WaterShader][UV] min_u=$minU');
    print('[WaterShader][UV] max_u=$maxU');
    print('[WaterShader][UV] min_v=$minV');
    print('[WaterShader][UV] max_v=$maxV');
    print('[WaterShader][UV] first=${uv[0]}');
    print('[WaterShader][UV] last=${uv[uv.size() - 1]}');

    final firstCount = math.min(4, uv.size());
    final lastStart = math.max(0, uv.size() - 4);

    for (int i = 0; i < firstCount; i++) {
      print('[WaterShader][UV] first_$i=${uv[i]}');
    }

    for (int i = lastStart; i < uv.size(); i++) {
      print('[WaterShader][UV] last_$i=${uv[i]}');
    }
  }

  // ---------------------------------------------------------------------------
  // Water
  // ---------------------------------------------------------------------------

  // ignore: unused_element
  void _drawWater(Vector2 c, double r) {
    if (_waterLevel <= 0.001) return;

    final shouldWobble =
        _state == WasherState.wash || _state == WasherState.rinse;

    final wobble = shouldWobble ? math.sin(_t * 1.8) * 1.6 : 0.0;

    final rx = r * 0.96;
    final ry = r * 0.82;

    final top = c.y - ry;
    final bot = c.y + ry;

    final lineY = bot - (bot - top) * _waterLevel + wobble;

    final poly = _ellipseSegmentBelowY(c, rx, ry, lineY, steps: 72);
    if (poly.size() < 3) return;

    final cols = PackedColorArray();
    for (int i = 0; i < poly.size(); i++) {
      final p = poly[i];
      final tt = ((p.y - top) / (bot - top)).clamp(0.0, 1.0);

      final a = 0.18 + tt * 0.22;
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
      Color.fromRGBA(0.92, 0.98, 1.0, 0.16),
      width: 1.8,
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

    final n = (2 + _foam * 5).toInt();

    for (int i = 0; i < n; i++) {
      final a = (i * 1.95) + _t * 0.45;
      final px = c.x + math.cos(a) * r * (0.16 + (i % 3) * 0.12);
      final py = c.y - r * 0.10 + math.sin(a * 1.18) * r * 0.24;

      final rad = 2.0 + (i % 3) * 1.3;
      final alpha = 0.035 + _foam * 0.065;

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

  // ignore: unused_element
  void _drawGlassHighlights(Vector2 c, double r, double angle) {
    // Fixed glass reflections, aligned with the hatch geometry.
    final slant = _rotateVector(Vector2(x: -0.78, y: 0.63), angle);
    final ortho = Vector2(x: -slant.y, y: slant.x);

    // Main broad reflection.
    final base = c + _rotateVector(Vector2(x: r * 0.08, y: -r * 0.02), angle);
    final lenA = r * 0.90;
    final wA = r * 0.17;

    final a0 = base + slant * (-lenA * 0.52) + ortho * wA;
    final a1 = base + slant * (lenA * 0.48) + ortho * wA;
    final a2 = base + slant * (lenA * 0.48) - ortho * wA;
    final a3 = base + slant * (-lenA * 0.52) - ortho * wA;

    _drawQuad(a0, a1, a2, a3, highlightA);

    // Secondary narrow parallel reflection.
    final base2 =
        base + _rotateVector(Vector2(x: r * 0.32, y: r * 0.15), angle);
    final lenB = r * 0.72;
    final wB = r * 0.035;

    final b0 = base2 + slant * (-lenB * 0.52) + ortho * wB;
    final b1 = base2 + slant * (lenB * 0.48) + ortho * wB;
    final b2 = base2 + slant * (lenB * 0.48) - ortho * wB;
    final b3 = base2 + slant * (-lenB * 0.52) - ortho * wB;

    _drawQuad(b0, b1, b2, b3, highlightB);
  }

  // ---------------------------------------------------------------------------
  // Steam / mist
  // ---------------------------------------------------------------------------

  void _drawSteam(Vector2 c, double r) {
    if (_steam <= 0.01) return;

    final innerR = math.max(0.0, r - ringThickness - 8.0);
    const plumeCount = 3;

    for (int i = 0; i < plumeCount; i++) {
      final phase = _t * 0.9 + i * 0.85;
      final ring = 0.18 + i * 0.12;
      final swirl = phase + i * 0.42;

      final x = c.x + math.cos(swirl) * innerR * ring * 0.70;
      final y =
          c.y + math.sin(swirl * 1.05) * innerR * ring * 0.44 - innerR * 0.06;

      final rx = 5.8 + i * 1.1;
      final ry = 3.2 + i * 0.6;

      final alpha = (0.045 + i * 0.006) * _steam;

      _drawEllipseFilledLocal(
        center: Vector2(x: x, y: y),
        rx: rx,
        ry: ry,
        color: Color.fromRGBA(steamCol.r, steamCol.g, steamCol.b, alpha),
        steps: 42,
      );
    }

    // Base mist inside the glass.
    _drawEllipseFilledLocal(
      center: Vector2(x: c.x, y: c.y + innerR * 0.07),
      rx: innerR * 0.78,
      ry: innerR * 0.28,
      color: Color.fromRGBA(0.86, 0.93, 0.98, 0.055 * _steam),
      steps: 56,
    );
  }

  // ---------------------------------------------------------------------------
  // Rotor / spin blur
  // ---------------------------------------------------------------------------

  void _drawSpinRotor(Vector2 c, double r) {
    final speedN = (_spinSpeed / 3.6).clamp(0.0, 1.0);
    if (speedN <= 0.035) return;

    if (speedN > 0.70) {
      _drawEllipseFilledLocal(
        center: c,
        rx: r * 0.58,
        ry: r * 0.22,
        color: Color.fromRGBA(
          rotorFastCol.r,
          rotorFastCol.g,
          rotorFastCol.b,
          0.025 + speedN * 0.035,
        ),
        steps: 48,
        rotation: _drumAngle,
      );
    }

    const bladeCount = 3;
    final hubR = r * 0.10;
    final bladeLen = r * (0.44 + speedN * 0.08);
    final w0 = r * (0.105 + speedN * 0.018);
    final w1 = r * (0.052 + speedN * 0.010);
    final bladeAlpha = 0.16 - speedN * 0.045;

    for (int i = 0; i < bladeCount; i++) {
      final a = _drumAngle + i * (2.0 * math.pi / bladeCount);
      final dir = Vector2(x: math.cos(a), y: math.sin(a));
      final ortho = Vector2(x: -dir.y, y: dir.x);

      final s = c + dir * hubR;
      final e = c + dir * bladeLen;

      _drawQuad(
        s + ortho * w0,
        e + ortho * w1,
        e - ortho * w1,
        s - ortho * w0,
        Color.fromRGBA(rotorCol.r, rotorCol.g, rotorCol.b, bladeAlpha),
      );
    }

    drawCircle(
      c,
      r * (0.080 + speedN * 0.015),
      Color.fromRGBA(
        rotorCol.r,
        rotorCol.g,
        rotorCol.b,
        0.10 + speedN * 0.06,
      ),
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

  PackedVector2Array _quadPolygon(
    Vector2 p0,
    Vector2 p1,
    Vector2 p2,
    Vector2 p3,
  ) {
    final pts = PackedVector2Array();
    pts.append(p0);
    pts.append(p1);
    pts.append(p2);
    pts.append(p3);
    return pts;
  }

  PackedVector2Array _ellipsePolygon({
    required Vector2 center,
    required double rx,
    required double ry,
    int steps = 64,
    double rotation = 0.0,
    Vector2? rotationOrigin,
  }) {
    final pts = PackedVector2Array();
    final origin = rotationOrigin ?? Vector2(x: 0, y: 0);

    for (int i = 0; i < steps; i++) {
      final t = (i / steps) * 2.0 * math.pi;

      final p = Vector2(
        x: center.x + rx * math.cos(t),
        y: center.y + ry * math.sin(t),
      );

      pts.append(_rotatePoint(p, rotation, origin: origin));
    }

    return pts;
  }

  PackedVector2Array _ellipseUv({int steps = 64}) {
    final uv = PackedVector2Array();

    for (int i = 0; i < steps; i++) {
      final t = (i / steps) * 2.0 * math.pi;
      final x = math.cos(t);
      final y = math.sin(t);

      uv.append(Vector2(
        x: x * 0.5 + 0.5,
        y: y * 0.5 + 0.5,
      ));
    }

    return uv;
  }

  (PackedVector2Array, PackedVector2Array) _glassHighlightPolygons(
    Vector2 c,
    double r,
    double angle,
  ) {
    final slant = _rotateVector(Vector2(x: -0.78, y: 0.63), angle);
    final ortho = Vector2(x: -slant.y, y: slant.x);

    final base = c + _rotateVector(Vector2(x: r * 0.08, y: -r * 0.02), angle);
    final lenA = r * 0.90;
    final wA = r * 0.17;

    final a0 = base + slant * (-lenA * 0.52) + ortho * wA;
    final a1 = base + slant * (lenA * 0.48) + ortho * wA;
    final a2 = base + slant * (lenA * 0.48) - ortho * wA;
    final a3 = base + slant * (-lenA * 0.52) - ortho * wA;

    final base2 =
        base + _rotateVector(Vector2(x: r * 0.32, y: r * 0.15), angle);
    final lenB = r * 0.72;
    final wB = r * 0.035;

    final b0 = base2 + slant * (-lenB * 0.52) + ortho * wB;
    final b1 = base2 + slant * (lenB * 0.48) + ortho * wB;
    final b2 = base2 + slant * (lenB * 0.48) - ortho * wB;
    final b3 = base2 + slant * (-lenB * 0.52) - ortho * wB;

    return (_quadPolygon(a0, a1, a2, a3), _quadPolygon(b0, b1, b2, b3));
  }

  void _drawEllipseFilledLocal({
    required Vector2 center,
    required double rx,
    required double ry,
    required Color color,
    int steps = 64,
    double rotation = 0.0,
    Vector2? rotationOrigin,
  }) {
    final pts = PackedVector2Array();
    final origin = rotationOrigin ?? Vector2(x: 0, y: 0);

    for (int i = 0; i < steps; i++) {
      final t = (i / steps) * 2.0 * math.pi;

      final p = Vector2(
        x: center.x + rx * math.cos(t),
        y: center.y + ry * math.sin(t),
      );

      pts.append(_rotatePoint(p, rotation, origin: origin));
    }

    drawColoredPolygon(pts, color);
  }

  Vector2 _rotateVector(Vector2 point, double angle) {
    final ca = math.cos(angle);
    final sa = math.sin(angle);

    return Vector2(
      x: point.x * ca - point.y * sa,
      y: point.x * sa + point.y * ca,
    );
  }

  Vector2 _rotatePoint(Vector2 point, double angle, {required Vector2 origin}) {
    return origin + _rotateVector(point - origin, angle);
  }
}
