/* The player page: one baked scene (scene.bin) painted on the canvas, turning once every thirty seconds while it plays its loop.
   A mouse or pen drag, or the arrow keys on the focused canvas, turn and tilt it; a finger only turns it, so an upright swipe still
   scrolls the page. A let-go drag coasts back into the slow turn and the resting tilt. With less motion asked for it holds still
   until moved. The stage's data-ready flag is "true" once a first frame has really finished and "false" once it will not draw, and
   until "true" the still picture (still.png) is what shows. */
import { frame, init, surface } from 'vgpu';

import { TILT_LIMIT } from './camera.js';
import { createPainter } from './painter.js';
import { loadScene } from './scene.js';

// one turn every thirty seconds, in radians a second
const CRUISE = (Math.PI * 2) / 30;
// how quickly a let-go turn eases back to the cruise, and a flicked tilt slows (seconds)
const SETTLE = 0.9;
const COAST = 0.35;
// how long after a let-go or a key the tilt starts home, and how quickly it goes (seconds)
const RETURN_AFTER = 0.8;
const RETURN = 1.2;
// how quickly a key's step lands (seconds), and how far one press turns and tilts
const KEY_SETTLE = 0.18;
const KEY_TURN = (20 * Math.PI) / 180;
const KEY_TILT = (12 * Math.PI) / 180;
// the fastest a flick sets it turning and tilting (radians a second)
const FASTEST_TURN = Math.PI * 2;
const FASTEST_TILT = Math.PI;
// a frame after a long pause counts as this long, so nothing jumps (seconds)
const LONGEST_STEP = 1 / 30;
// the pointer's last moments that count towards a flick (milliseconds)
const FLICK_WINDOW = 100;
// the most device pixels a CSS pixel counts for, so a scene has about the same art pixels on any screen
const MOST_DEVICE_PIXELS = 3;

const KEYS = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, 1], ArrowDown: [0, -1] };

const box = document.querySelector('.stage'),
  canvas = box.querySelector('canvas'),
  note = document.querySelector('.note');

const clampTilt = pitch => Math.max(-TILT_LIMIT, Math.min(TILT_LIMIT, pitch));
const clampSpeed = (speed, most) => Math.max(-most, Math.min(most, speed));
const ease = (dt, over) => 1 - Math.exp(-dt / over);
const settle = (owed, dt) => (Math.abs(owed) < 1e-4 ? owed : owed * ease(dt, KEY_SETTLE));

function showStill(words) {
  box.dataset.ready = 'false';
  note.textContent = words;
}

// the device and the file are asked for together; a device that came up is given back if anything after it fails
async function play() {
  const [started, loaded] = await Promise.allSettled([init(), loadScene('scene.bin')]);
  if (started.status === 'rejected') throw started.reason;
  const gpu = started.value;
  let disposed = false;
  gpu.lost.then(() => disposed || showStill('The live scene stopped. This is its still picture.'));
  try {
    if (loaded.status === 'rejected') throw loaded.reason;
    await run(gpu, loaded.value);
  } catch (error) {
    disposed = true;
    gpu.dispose();
    throw error;
  }
}

async function run(gpu, scene) {
  const { header } = scene,
    stage = surface(gpu, canvas, { autoResize: false, alphaMode: 'opaque', label: 'stage' }),
    painter = createPainter(gpu, scene),
    calmQuery = matchMedia('(prefers-reduced-motion: reduce)');

  const fit = () => {
    const ratio = Math.min(devicePixelRatio, MOST_DEVICE_PIXELS),
      width = Math.max(1, Math.round(canvas.clientWidth * ratio)),
      height = Math.max(1, Math.round(canvas.clientHeight * ratio));
    stage.resize([width, height]);
    return painter.resize(width, height);
  };
  let grid = fit();
  await painter.compile(stage);

  let calm = calmQuery.matches,
    held = false,
    // how far it has turned from the opening yaw (its near side to the right), its tilt, and the time into its loop
    turn = 0,
    pitch = header.camPitch,
    seconds = 0,
    turnSpeed = calm ? 0 : CRUISE,
    tiltSpeed = 0,
    // seconds since a let-go or a key, for the tilt's way home
    since = Infinity,
    // turning and tilting owed to keys, and to drags since the last frame
    keyedTurn = 0,
    keyedTilt = 0,
    draggedTurn = 0,
    draggedTilt = 0,
    drawn = null,
    last = null;

  // radians per CSS pixel, so the scene's near edge keeps up with the pointer
  const radians = pixels => {
    const devicePerCss = canvas.clientWidth > 0 ? canvas.width / canvas.clientWidth : 1;
    return pixels / Math.max(1, (grid.focal * grid.scale * header.radius * grid.zoom) / (devicePerCss * header.camDist));
  };

  calmQuery.addEventListener('change', event => {
    calm = event.matches;
    if (calm) {
      draggedTurn += keyedTurn;
      draggedTilt += keyedTilt;
      keyedTurn = keyedTilt = turnSpeed = tiltSpeed = 0;
    } else if (!held) turnSpeed = CRUISE;
  });

  // one pointer at a time: a mouse, a pen or the first finger down; a finger only turns
  let pointer = null,
    tilts = true,
    moves = [];
  canvas.addEventListener('pointerdown', event => {
    if (pointer !== null) return;
    pointer = event.pointerId;
    tilts = event.pointerType !== 'touch';
    canvas.setPointerCapture(pointer);
    moves = [[event.timeStamp, event.clientX, event.clientY]];
    held = true;
    turnSpeed = tiltSpeed = 0;
  });
  canvas.addEventListener('pointermove', event => {
    if (event.pointerId !== pointer) return;
    const [, x, y] = moves[moves.length - 1];
    draggedTurn += radians(event.clientX - x);
    if (tilts) draggedTilt += radians(event.clientY - y);
    moves.push([event.timeStamp, event.clientX, event.clientY]);
    moves = moves.filter(([at]) => at >= event.timeStamp - FLICK_WINDOW);
  });
  const letGo = event => {
    if (event.pointerId !== pointer) return;
    pointer = null;
    held = false;
    since = 0;
    const [t0, x0, y0] = moves[0],
      [t1, x1, y1] = moves[moves.length - 1],
      flicked = !calm && event.timeStamp - t1 < FLICK_WINDOW && t1 > t0,
      span = (t1 - t0) / 1000;
    turnSpeed = flicked ? clampSpeed(radians((x1 - x0) / span), FASTEST_TURN) : 0;
    tiltSpeed = flicked && tilts ? clampSpeed(radians((y1 - y0) / span), FASTEST_TILT) : 0;
  };
  canvas.addEventListener('pointerup', letGo);
  canvas.addEventListener('pointercancel', letGo);

  canvas.addEventListener('keydown', event => {
    const step = KEYS[event.key];
    if (!step) return;
    event.preventDefault();
    since = 0;
    if (calm) {
      draggedTurn += step[0] * KEY_TURN;
      draggedTilt += step[1] * KEY_TILT;
    } else {
      keyedTurn += step[0] * KEY_TURN;
      keyedTilt += step[1] * KEY_TILT;
    }
  });

  new ResizeObserver(() => {
    grid = fit();
    drawn = null;
  }).observe(canvas);

  const tick = now => {
    const dt = last === null ? 0 : Math.min((now - last) / 1000, LONGEST_STEP);
    last = now;
    turn += draggedTurn;
    pitch = clampTilt(pitch + draggedTilt);
    draggedTurn = draggedTilt = 0;
    if (!calm) {
      seconds = (seconds + dt) % header.loop;
      since += dt;
      turnSpeed += ((held ? 0 : CRUISE) - turnSpeed) * ease(dt, SETTLE);
      tiltSpeed *= 1 - ease(dt, COAST);
      const turnStep = settle(keyedTurn, dt),
        tiltStep = settle(keyedTilt, dt);
      keyedTurn -= turnStep;
      keyedTilt -= tiltStep;
      turn += turnSpeed * dt + turnStep;
      pitch += tiltSpeed * dt + tiltStep;
      if (!held) pitch += (header.camPitch - pitch) * ease(dt, RETURN) * Math.min(1, Math.max(0, (since - RETURN_AFTER) / RETURN_AFTER));
      const clamped = clampTilt(pitch);
      if (clamped !== pitch) tiltSpeed = 0;
      pitch = clamped;
    }
    if (!calm || drawn?.turn !== turn || drawn.pitch !== pitch) {
      drawn = { turn, pitch };
      frame(gpu, f => painter.encode(f, { yaw: header.camYaw - turn, pitch, seconds }, stage));
    }
    requestAnimationFrame(tick);
  };
  // the opening view drawn once, and finished on the graphics card, before the still gives way to the canvas
  frame(gpu, f => painter.encode(f, { yaw: header.camYaw, pitch, seconds }, stage));
  await gpu.settled();
  box.dataset.ready = 'true';
  requestAnimationFrame(tick);
}

if (!navigator.gpu) showStill('This browser cannot draw the live scene. This is its still picture.');
else
  play().catch(error => {
    showStill('The live scene could not start. This is its still picture.');
    console.error(error);
  });
