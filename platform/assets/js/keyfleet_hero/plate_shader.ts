/**
 * The plate "Buy Agent Fleet Access Key" stands on: a slab of small hex tiles
 * in a colour of its own, raised off the page. One fullscreen pass over a
 * clear canvas a little larger than the plate, with premultiplied alpha, so
 * the room around the slab holds its jagged edge and its shadow. Each tile is
 * a short hex prism: its face lifted by `raise.x`, its side showing below the
 * face, the slab's floor in the gaps. `raise.y` brings the tiles up one after
 * another from the left as the plate first appears.
 */
export const plateWgsl = /* wgsl */ `
struct Params {
  // Width and height in device pixels, the tile size, device pixels per CSS pixel.
  size: vec4f,
  // The plate's box, left top right bottom, in device pixels.
  slab: vec4f,
  // How high the faces stand in device pixels, how far the tiles have risen
  // (0..1), how much light the faces take, and how dark the shadow is.
  raise: vec4f,
  face: vec4f,
  side: vec4f,
}
@group(0) @binding(0) var<uniform> params: Params;

// Pointy-top hexagons, one unit between neighbouring centres across a row:
// the point's offset from its cell's centre, and how far it is toward the
// nearest edge, 0.5 on the edge itself.
fn hex(p: vec2f) -> vec3f {
  let r = vec2f(1.0, 1.7320508);
  let h = r * 0.5;
  let a = p - r * floor(p / r) - h;
  let b = (p - h) - r * floor((p - h) / r) - h;
  let g = select(b, a, dot(a, a) < dot(b, b));
  let q = abs(g);
  return vec3f(g, max(dot(q, vec2f(0.5, 0.8660254)), q.x));
}

fn over(below: vec4f, rgb: vec3f, alpha: f32) -> vec4f {
  return vec4f(rgb * alpha + below.rgb * (1.0 - alpha), alpha + below.a * (1.0 - alpha));
}

// The tile under a point, laid out from the plate's corner.
fn tile(p: vec2f) -> vec3f {
  return hex((p - params.slab.xy) / params.size.z);
}

fn centre(p: vec2f, h: vec3f) -> vec2f {
  return p - h.xy * params.size.z;
}

// The slab is every tile whose centre falls on the plate, give or take a
// quarter of a tile, so its edge follows the tiles rather than a rectangle.
fn onSlab(c: vec2f) -> bool {
  let e = params.size.z * 0.25;
  return all(c >= params.slab.xy - vec2f(e)) && all(c <= params.slab.zw + vec2f(e));
}

// How high this tile stands: the tiles nearer the left rise first.
fn height(c: vec2f) -> f32 {
  let order = clamp((c.x - params.slab.x) / max(params.slab.z - params.slab.x, 1.0), 0.0, 1.0);
  let t = clamp(params.raise.y * 1.6 - order * 0.6, 0.0, 1.0);
  return params.raise.x * t * t * (3.0 - 2.0 * t);
}

fn sdBox(p: vec2f, half: vec2f, radius: f32) -> f32 {
  let q = abs(p) - half + vec2f(radius);
  return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let p = uv * params.size.xy;
  let cell = params.size.z;
  let ratio = params.size.w;
  let lift = params.raise.x;
  let aa = 1.0 / cell;
  let floorRgb = params.side.rgb * 0.84;

  var color = vec4f(0.0);

  // The slab's shadow on the page, further and softer the higher it stands.
  let half = (params.slab.zw - params.slab.xy) * 0.5 + vec2f(cell * 0.3);
  let mid = (params.slab.xy + params.slab.zw) * 0.5 + vec2f(0.0, lift * 0.9 + 1.5 * ratio);
  let blur = 5.0 * ratio + lift * 1.4;
  let shade = 1.0 - smoothstep(-blur, blur, sdBox(p - mid, half, cell * 0.4));
  color = over(color, vec3f(0.0), params.raise.w * shade);

  // The floor between the tiles.
  let base = tile(p);
  if (onSlab(centre(p, base))) {
    color = over(color, floorRgb, 1.0);
  }

  // The tiles' sides, below each face down to the floor, darker lower down.
  for (var k = 1; k <= 6; k += 1) {
    let t = lift * f32(k) / 6.0;
    let q = p + vec2f(0.0, t);
    let h = tile(q);
    let c = centre(q, h);
    if (onSlab(c) && t <= height(c) + 0.5) {
      let m = 1.0 - smoothstep(0.47 - aa, 0.47, h.z);
      color = over(color, params.side.rgb * (0.82 + 0.18 * f32(k) / 6.0), m);
    }
  }

  // The faces, lit from above: a brighter top edge, a darker bottom edge.
  let guess = p + vec2f(0.0, lift);
  let near = tile(guess);
  let q = p + vec2f(0.0, height(centre(guess, near)));
  let h = tile(q);
  if (onSlab(centre(q, h))) {
    let m = 1.0 - smoothstep(0.47 - aa, 0.47, h.z);
    let edge = smoothstep(0.36, 0.47, h.z);
    let top = clamp(-h.y * 2.4, -1.0, 1.0);
    var rgb = params.face.rgb * (1.0 + edge * 0.18 * top);
    rgb = mix(rgb, vec3f(1.0), params.raise.z * 0.10);
    color = over(color, min(rgb, vec3f(1.0)), m);
  }

  return color;
}`
