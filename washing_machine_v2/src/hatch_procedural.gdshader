shader_type canvas_item;

uniform float fill_level : hint_range(0.0, 1.0) = 0.0;   // 0 vide, 1 plein
uniform float spin_angle = 0.0;                           // radians
uniform float spin_strength : hint_range(0.0, 1.0) = 0.0; // 0 idle, 1 spin
uniform float foam : hint_range(0.0, 1.0) = 0.0;          // 0 off, 1 on

// paramètres visuels
uniform float radius : hint_range(0.2, 0.5) = 0.44;
uniform float edge_soft : hint_range(0.0, 0.05) = 0.015;

float sCircle(vec2 uv, vec2 c, float r, float soft) {
  float d = distance(uv, c);
  return smoothstep(r, r - soft, d);
}

float ring(vec2 uv, vec2 c, float rOuter, float rInner, float soft) {
  float o = sCircle(uv, c, rOuter, soft);
  float i = sCircle(uv, c, rInner, soft);
  return clamp(o - i, 0.0, 1.0);
}

void fragment() {
  vec2 uv = UV;
  vec2 c = vec2(0.5, 0.5);

  // base mask hublot
  float hatch = sCircle(uv, c, radius, edge_soft);

  // --------- Drum (spokes) ----------
  vec2 p = uv - c;
  float ang = atan(p.y, p.x) + spin_angle;
  float r = length(p);

  // spokes: 8 rayons
  float spokes = abs(sin(ang * 4.0));
  spokes = smoothstep(0.70, 0.95, spokes); // finesse
  float drum = smoothstep(radius * 0.80, radius * 0.10, r); // plus fort au centre
  drum *= spokes;

  // fond tambour
  vec3 drumCol = mix(vec3(0.62,0.66,0.70), vec3(0.52,0.56,0.60), r / (radius*0.8));
  drumCol += drum * 0.08;

  // --------- Water ----------
  // coupe horizontale (niveau)
  float waterCut = smoothstep(1.0 - fill_level, 1.0 - fill_level - 0.02, uv.y);
  // wobble léger quand ça tourne
  float wob = sin((uv.x + spin_angle*0.15) * 18.0) * 0.01 * spin_strength;
  waterCut *= smoothstep(1.0 - fill_level + wob, 1.0 - fill_level + wob - 0.02, uv.y);

  vec3 waterCol = vec3(0.55, 0.70, 0.82);
  waterCol = mix(waterCol, vec3(0.45, 0.62, 0.78), uv.y);

  // mousse (foam) : bruit simple via sin
  float foamBand = smoothstep(1.0 - fill_level - 0.02, 1.0 - fill_level + 0.02, uv.y);
  float foamNoise = (sin((uv.x*60.0) + spin_angle*2.0) * 0.5 + 0.5);
  float foamMask = foam * foamBand * smoothstep(0.35, 0.8, foamNoise);

  // --------- Glass / highlights ----------
  // vignette (verre)
  float v = 1.0 - clamp(length(p) / radius, 0.0, 1.0);
  vec3 glassTint = vec3(0.92, 0.94, 0.97) * (0.18 + 0.25*v);

  // reflet haut-gauche doux
  float hl = smoothstep(0.35, 0.0, distance(uv, c + vec2(-0.12, -0.12)));
  hl *= 0.35;

  // --------- AO / inner shadow ----------
  float inner = sCircle(uv, c, radius*0.98, edge_soft);
  float inner2 = sCircle(uv, c, radius*0.75, edge_soft);
  float ao = clamp(inner - inner2, 0.0, 1.0) * 0.35;

  // --------- Compose ----------
  vec3 col = drumCol;

  // eau par-dessus
  col = mix(col, waterCol, waterCut * 0.9);

  // mousse blanche
  col = mix(col, vec3(0.95,0.97,0.99), foamMask);

  // verre par-dessus
  col = col + glassTint + vec3(hl);

  // assombrir bords internes (AO)
  col *= (1.0 - ao);

  // anneau simple (si tu veux le faire ici aussi)
  float rg = ring(uv, c, radius*1.02, radius*0.92, edge_soft);
  col = mix(col, vec3(0.78,0.76,0.86), rg*0.9);

  COLOR = vec4(col, hatch);
}
