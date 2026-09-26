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
  /// WasherBody supplies a single projection for the entire hatch.
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
  double ringThickness = 7.0;

  /// Local geometry stays circular; perspective comes from WasherBody.
  static const double hatchGeometryAngleRad = 0.0;

  /// Keeps the glass slightly inset from the rim.
  double glassInset = 3.0;

  /// Maximum width of the inner left shadow, before the face projection.
  double innerLeftShadowWidth = 9.0;

  // ---------------------------------------------------------------------------
  // Palette
  // ---------------------------------------------------------------------------

  // Pastel rim colors.
  final Color innerLeftShadow = Color.fromRGBA(0.59, 0.56, 0.73, 0.48);
  final Color rimShadow = Color.fromRGBA(0.38, 0.30, 0.52, 0.075);
  final Color rimOuter = Color.fromRGBA(0.855, 0.82, 0.96, 1.0);
  final Color rimInnerLight = Color.fromRGBA(0.82, 0.79, 0.92, 1.0);

  // Inner drum / glass colors.
  final Color innerDrumBase = Color.fromRGBA(0.67, 0.73, 0.76, 1.0);
  final Color glassWash = Color.fromRGBA(0.90, 0.96, 1.0, 0.08);

  // Highlights.
  final Color highlightA = Color.fromRGBA(0.92, 0.97, 1.0, 0.40);
  final Color highlightB = Color.fromRGBA(0.92, 0.97, 1.0, 0.32);

  // Liquids / bubbles.
  final Color waterTop = Color.fromRGBA(0.64, 0.80, 0.92, 0.30);
  final Color waterBottom = Color.fromRGBA(0.42, 0.63, 0.80, 0.52);
  final Color bubbleCol = Color.fromRGBA(0.92, 1.0, 0.96, 0.18);

  // Rotor / spin blur.
  final Color rotorCol = Color.fromRGBA(0.77, 0.87, 0.97, 0.28);
  final Color rotorFastCol = Color.fromRGBA(0.84, 0.92, 0.99, 0.18);

  // Steam / mist.
  final Color steamCol = Color.fromRGBA(0.86, 0.84, 0.94, 0.19);

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
  bool debugWashBubbles = false;
  bool debugRinseSteam = false;

  Polygon2D? _waterLayer;
  ShaderMaterial? _waterMaterial;
  Node2D? _hatchEffectsLayer;
  final List<Polygon2D> _bubbleLayers = [];
  final List<Polygon2D> _steamLayers = [];
  Polygon2D? _steamMistLayer;
  Node2D? _hatchOverlay;
  Polygon2D? _glassVeilLayer;
  Polygon2D? _innerLeftShadowLayer;
  Polygon2D? _highlightALayer;
  Polygon2D? _highlightBLayer;
  bool _waterShaderLoaded = false;
  bool _waterShaderReadyLogged = false;
  bool _hatchEffectsReadyLogged = false;
  bool _debugWashBubblesLogged = false;
  bool _debugRinseSteamLogged = false;
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
        _targetFoam = 0.0;
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
    _updateEffectLayers();
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
    _setupHatchEffectsLayer();
    _setupHatchOverlay();
    _rebuildLayerGeometry();
    _updateWaterShaderUniforms();
    _updateEffectLayers();
    _syncLayerVisibility();
    _logWaterShaderReady();
    _logHatchEffectsReady();

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
    final effectiveSpinTarget = _effectiveSpinTarget();
    _spinSpeed = _spinSpeed + (effectiveSpinTarget - _spinSpeed) * aSpin;

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
    _updateEffectLayers();
    queueRedraw();
  }

  double _effectiveSpinTarget() {
    switch (_state) {
      case WasherState.wash:
        return math.sin(_t * 1.05) * _targetSpinSpeed * 1.12;

      case WasherState.rinse:
        return math.sin(_t * 1.90) * _targetSpinSpeed * 0.82;

      case WasherState.idle:
      case WasherState.fill:
      case WasherState.spin:
      case WasherState.done:
        return _targetSpinSpeed;
    }
  }

  void _alignToBody() {
    final n = getNodeOrNull(bodyPath);
    if (n is! WasherBody) return;

    setGlobalTransform(n.getHatchTransformWorld());
  }

  // ---------------------------------------------------------------------------
  // Draw
  // ---------------------------------------------------------------------------

  @override
  void vDraw() {
    final c = Vector2(x: 0, y: 0);

    final innerR = math.max(0.0, outerRadius - ringThickness);
    final glassR = math.max(0.0, innerR - glassInset);
    final rimRy = outerRadius;
    final innerRy = innerR;
    final glassRy = glassR;
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

    // Light rim around the glass; depth shading is confined to the left overlay.
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

    // Neutral inner drum base, seen through the glass overlay.
    _drawEllipseFilledLocal(
      center: c + Vector2(x: -1.2, y: -0.6),
      rx: glassR * 0.98,
      ry: glassRy,
      color: innerDrumBase,
      steps: 80,
      rotation: tilt,
    );

    // Keep the idle glass uniform; moving drum details are drawn below.
    _syncLayerVisibility();

    if (_state == WasherState.wash ||
        _state == WasherState.rinse ||
        _state == WasherState.spin ||
        _state == WasherState.done) {
      // Rotor stays behind the shader water layer, glass veil, and static highlights.
      _drawSpinRotor(c, glassR - 6.0);
    }
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

  void _setupHatchEffectsLayer() {
    if (_hatchEffectsLayer != null) return;

    final effects = Node2D();
    effects.setName('HatchEffectsLayer');
    effects.setZIndex(2);

    for (int i = 0; i < 6; i++) {
      final bubble = _makeOverlayPolygon(
        'Bubble${i + 1}',
        Color.fromRGBA(bubbleCol.r, bubbleCol.g, bubbleCol.b, 0.0),
      );
      bubble.setVisible(false);
      _bubbleLayers.add(bubble);
      effects.addChild(bubble);
    }

    for (int i = 0; i < 3; i++) {
      final steam = _makeOverlayPolygon(
        'Steam${i + 1}',
        Color.fromRGBA(steamCol.r, steamCol.g, steamCol.b, 0.0),
      );
      steam.setVisible(false);
      _steamLayers.add(steam);
      effects.addChild(steam);
    }

    _steamMistLayer = _makeOverlayPolygon(
      'SteamMist',
      Color.fromRGBA(0.86, 0.93, 0.98, 0.0),
    );
    _steamMistLayer?.setVisible(false);
    effects.addChild(_steamMistLayer);

    _hatchEffectsLayer = effects;
    addChild(effects);
  }

  void _setupHatchOverlay() {
    if (_hatchOverlay != null) return;

    final overlay = Node2D();
    overlay.setName('HatchOverlay');
    overlay.setZIndex(3);

    _glassVeilLayer = _makeOverlayPolygon(
      'GlassVeil',
      glassWash,
    );
    _innerLeftShadowLayer =
        _makeOverlayPolygon('InnerLeftShadow', innerLeftShadow);
    _highlightALayer = _makeOverlayPolygon('GlassHighlightMain', highlightA);
    _highlightBLayer =
        _makeOverlayPolygon('GlassHighlightSecondary', highlightB);

    overlay.addChild(_glassVeilLayer);
    overlay.addChild(_innerLeftShadowLayer);
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
    final glassRy = glassR;
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
      center: c + Vector2(x: -1.2, y: -0.6),
      rx: glassR * 0.98,
      ry: glassRy,
      steps: 72,
      rotation: tilt,
      rotationOrigin: c,
    ));

    _innerLeftShadowLayer?.setPolygon(_leftGlassShadowPolygon(c, glassR, tilt));

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
    _hatchEffectsLayer?.setVisible(
      debugWashBubbles ||
          debugRinseSteam ||
          (_state == WasherState.wash && _foam > 0.01) ||
          ((_state == WasherState.rinse || _state == WasherState.done) &&
              _steam > 0.01),
    );
    _hatchOverlay?.setVisible(true);
  }

  void _updateEffectLayers() {
    final c = Vector2(x: 0, y: 0);
    final innerR = math.max(0.0, outerRadius - ringThickness);
    final glassR = math.max(0.0, innerR - glassInset);

    _clearEffectLayers();

    if (debugWashBubbles && !_debugWashBubblesLogged) {
      _debugWashBubblesLogged = true;
      print('[HatchEffects] debug bubbles=true');
    } else if (!debugWashBubbles) {
      _debugWashBubblesLogged = false;
    }

    if (debugRinseSteam && !_debugRinseSteamLogged) {
      _debugRinseSteamLogged = true;
      print('[HatchEffects] debug steam=true');
    } else if (!debugRinseSteam) {
      _debugRinseSteamLogged = false;
    }

    if (_state == WasherState.wash || debugWashBubbles) {
      _drawBubbles(c, glassR - 10.0, debug: debugWashBubbles);
    }

    if (_state == WasherState.rinse ||
        _state == WasherState.done ||
        debugRinseSteam) {
      _drawSteam(c, outerRadius, debug: debugRinseSteam);
    }

    _syncLayerVisibility();
  }

  void _clearEffectLayers() {
    for (final layer in _bubbleLayers) {
      layer.setVisible(false);
    }
    for (final layer in _steamLayers) {
      layer.setVisible(false);
    }
    _steamMistLayer?.setVisible(false);
  }

  void _setPolygonLayer(
    Polygon2D? layer, {
    required PackedVector2Array polygon,
    required Color color,
  }) {
    if (layer == null) return;

    layer.setPolygon(polygon);
    layer.setColor(color);
    layer.setVisible(true);
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

  void _logHatchEffectsReady() {
    if (_hatchEffectsReadyLogged) return;
    _hatchEffectsReadyLogged = true;

    print(
        '[HatchEffects] HatchEffectsLayer exists=${_hatchEffectsLayer != null}');
    print(
        '[HatchEffects] HatchEffectsLayer visible=${_hatchEffectsLayer?.isVisible()}');
    print('[HatchEffects] z_index=${_hatchEffectsLayer?.getZIndex()}');
    print('[HatchEffects] bubble polygon count=${_bubbleLayers.length}');
    print('[HatchEffects] steam polygon count=${_steamLayers.length}');
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

  void _drawBubbles(Vector2 c, double r, {bool debug = false}) {
    final foam = debug ? math.max(_foam, math.max(_targetFoam, 0.32)) : _foam;
    if (foam <= 0.01) return;

    final n = (3 + foam * 7).round().clamp(4, 6);

    for (int i = 0; i < n; i++) {
      if (i >= _bubbleLayers.length) break;

      final a = (i * 1.62) + _t * 0.36;
      final rise = (_t * 0.16 + i * 0.19) % 1.0;
      final px = c.x +
          math.cos(a) * r * (0.18 + (i % 3) * 0.10) +
          math.sin(_t * 0.42 + i) * 1.8;
      final py =
          c.y + r * 0.26 - rise * r * 0.58 + math.sin(a * 1.12) * r * 0.045;

      final rad = 2.4 + (i % 3) * 1.35;
      final alpha = 0.095 + foam * 0.16;
      final color = debug
          ? Color.fromRGBA(0.45, 1.0, 0.0, 0.90)
          : Color.fromRGBA(bubbleCol.r, bubbleCol.g, bubbleCol.b, alpha);

      _setPolygonLayer(
        _bubbleLayers[i],
        polygon: _ellipsePolygon(
          center: Vector2(x: px, y: py),
          rx: rad,
          ry: rad,
          steps: 24,
        ),
        color: color,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Steam / mist
  // ---------------------------------------------------------------------------

  void _drawSteam(Vector2 c, double r, {bool debug = false}) {
    final steam =
        debug ? math.max(_steam, math.max(_targetSteam, 0.20)) : _steam;
    if (steam <= 0.01) return;

    final innerR = math.max(0.0, r - ringThickness - 8.0);
    const plumeCount = 3;

    for (int i = 0; i < plumeCount; i++) {
      final rise = (_t * (0.11 + i * 0.025) + i * 0.28) % 1.0;
      final phase = _t * (0.42 + i * 0.05) + i * 0.90;
      final x = c.x +
          (i - 1) * innerR * 0.24 -
          innerR * 0.08 +
          math.sin(phase) * innerR * 0.035;
      final y = c.y - innerR * (0.24 + rise * 0.42);

      final rx = 4.4 + i * 0.4;
      final ry = 10.8 + i * 1.2;

      final alpha = (0.140 + i * 0.018) * steam;
      final color = debug
          ? Color.fromRGBA(1.0, 0.28, 0.10, 0.90)
          : Color.fromRGBA(steamCol.r, steamCol.g, steamCol.b, alpha);

      _setPolygonLayer(
        _steamLayers[i],
        polygon: _ellipsePolygon(
          center: Vector2(x: x, y: y),
          rx: rx,
          ry: ry,
          steps: 42,
        ),
        color: color,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Rotor / spin blur
  // ---------------------------------------------------------------------------

  void _drawSpinRotor(Vector2 c, double r) {
    final speedN = (_spinSpeed.abs() / 3.6).clamp(0.0, 1.0);
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

  /// A crescent along the left glass edge, tapering to zero at top and bottom.
  /// The overlay keeps this fixed rim shadow in front of water and drum motion.
  PackedVector2Array _leftGlassShadowPolygon(
      Vector2 c, double r, double angle) {
    final center = c + Vector2(x: -1.2, y: -0.6);
    final rx = r * 0.98;
    final width = innerLeftShadowWidth.clamp(0.0, rx);
    const steps = 40;
    final points = PackedVector2Array();

    // Outer edge: follow the glass from top to bottom through its left side.
    for (int i = 0; i <= steps; i++) {
      final t = math.pi * i / steps;
      points.append(_rotatePoint(
        center + Vector2(x: -rx * math.sin(t), y: -r * math.cos(t)),
        angle,
        origin: c,
      ));
    }

    // Inner edge: return upward, leaving a smooth crescent between the edges.
    // The shared endpoints are omitted to avoid duplicate polygon vertices.
    for (int i = steps - 1; i > 0; i--) {
      final t = math.pi * i / steps;
      points.append(_rotatePoint(
        center + Vector2(x: -(rx - width) * math.sin(t), y: -r * math.cos(t)),
        angle,
        origin: c,
      ));
    }
    return points;
  }

  /// Two fixed light bands, drawn inside the glass before the face projection.
  /// Lengths and widths are relative to the glass radius, so resizing the hatch
  /// preserves their proportions. Neither band follows the rotating drum.
  (PackedVector2Array, PackedVector2Array) _glassHighlightPolygons(
    Vector2 c,
    double r,
    double angle,
  ) {
    final slant = _rotateVector(Vector2(x: -0.38, y: 0.925), angle);
    final ortho = Vector2(x: slant.y, y: -slant.x);

    final base = c + _rotateVector(Vector2(x: r * 0.14, y: -r * 0.03), angle);
    final lenA = r * 1.48;
    final wA = r * 0.16;

    final a0 = base - slant * (lenA * 0.5) - ortho * wA;
    final a1 = base + slant * (lenA * 0.5) - ortho * wA;
    final a2 = base + slant * (lenA * 0.5) + ortho * wA;
    final a3 = base - slant * (lenA * 0.5) + ortho * wA;

    final base2 =
        base + _rotateVector(Vector2(x: r * 0.32, y: r * 0.13), angle);
    final lenB = r * 1.28;
    final wB = r * 0.035;

    final b0 = base2 - slant * (lenB * 0.5) - ortho * wB;
    final b1 = base2 + slant * (lenB * 0.5) - ortho * wB;
    final b2 = base2 + slant * (lenB * 0.5) + ortho * wB;
    final b3 = base2 - slant * (lenB * 0.5) + ortho * wB;

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
