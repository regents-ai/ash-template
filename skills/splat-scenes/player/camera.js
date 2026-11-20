/* The camera and the art-pixel grid of a baked scene. The scene is framed for a stage three wide by two high; a narrower stage steps
   the camera back so the scene still fits across it, and the art pixels are sized so the scene is drawn as the kit's stills draw it. */

const FRAMED = 3 / 2;
// the steepest the view tilts over or under the scene, a little short of straight above or below
export const TILT_LIMIT = (86 * Math.PI) / 180;

// the grid for a stage this many screen pixels wide and high: { zoom, scale (screen pixels to an art pixel), columns, rows, focal }
export function gridFor(header, width, height) {
  const s = Math.min(1, width / height / FRAMED),
    detail = header.detail * s ** (1 / 4),
    span = 2 * Math.tan(header.fov / 2),
    scale = Math.min(18, Math.max(1, Math.round(height / (span * detail * (header.camDist / s))))),
    rows = Math.ceil(height / scale);
  return { zoom: s, scale, columns: Math.ceil(width / scale), rows, focal: rows / span };
}

// the camera at this yaw and pitch, looking at the scene's target from its distance over the grid's zoom: { eye, right, up, back, distance }
export function viewFrom(header, yaw, pitch, zoom) {
  const distance = header.camDist / zoom,
    back = [Math.cos(pitch) * Math.sin(yaw), Math.sin(pitch), Math.cos(pitch) * Math.cos(yaw)],
    level = Math.hypot(back[0], back[2]),
    right = [back[2] / level, 0, -back[0] / level],
    up = [back[1] * right[2] - back[2] * right[1], back[2] * right[0] - back[0] * right[2], back[0] * right[1] - back[1] * right[0]],
    [x, y, z] = header.camTarget;
  return { eye: [x + distance * back[0], y + distance * back[1], z + distance * back[2]], right, up, back, distance };
}
