/**
 * Draws the agent harbour with WebGPU through vgpu: an isometric sea of islands,
 * one ship for each agent. Loaded only once the harbour is really going to be shown.
 *
 * Each frame the sun draws its shadow map, the scene is drawn into a multisampled
 * target, and a last pass lays it on the page. Every mesh is instanced; the
 * islands and buildings are one instance, the ships and the smoke one each.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {draw, effect, frame, geometry, init, sampler, surface, target, uniforms, type Geometry, type Gpu} from "vgpu"
import {
  group,
  instances,
  orbitRig,
  orthographic,
  rigPose,
  viewMatrices,
  type CameraMatrices,
  type InstanceId,
  type Pose,
} from "vgpu/scene"
import {instanceGeometry} from "vgpu/scene/gpu"

import type {IslandRenderer} from "../canvas_island"
import {FORGE_SMOKE, INN_SMOKE, harbourMesh, puffMesh, shipMesh, VERTEX_FLOATS} from "./meshes"
import {partsWgsl, presentWgsl, shadowWgsl, waterWgsl} from "./shaders"
import {
  CRUISE_SPEED,
  ISLANDS,
  ISLETS,
  MAX_SHIPS,
  PLACES,
  parkFleet,
  stepFleet,
  syncFleet,
  waveHeight,
  type Agent,
  type Ship,
} from "./sim"

export type HarbourLook = {
  readonly night: boolean
  /** The page colour the sea fades into, as #rrggbb. */
  readonly haze: string
}

export type HarbourRenderer = IslandRenderer & {
  setAgents(agents: readonly Agent[]): void
  setLook(look: HarbourLook): void
  /** A visitor who asked for less motion gets one composed, unmoving harbour. */
  setCalm(calm: boolean): void
}

const SHADOW_SIZE = 2048
const SEA_SIZE = 44
const SEA_SEGMENTS = 132
const SHIP_SCALE = 0.95
const PUFFS = {forge: 8, inn: 4}
/** The moment a calm harbour is shown at: flags and sails mid-wave. */
const STILL_TIME = 2.4
/** Longest step the ships take, so a tab coming back does not jump the fleet. */
const MAX_STEP = 1 / 20

const DAY = {
  sun: normalize([0.55, 0.9, -0.35]),
  sunColor: [2.55, 2.4, 2.15],
  sky: [0.5, 0.6, 0.74],
  exposure: 1.0,
}
const NIGHT = {
  sun: normalize([-0.35, 0.85, -0.45]),
  sunColor: [0.36, 0.44, 0.7],
  sky: [0.07, 0.1, 0.19],
  exposure: 1.15,
}

export async function createHarbourRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<HarbourRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a harbour still on
  // screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })
  try {
    return await build(gpu, canvas, size, () => disposed, () => void (disposed = true))
  } catch (error) {
    disposed = true
    gpu.dispose()
    throw error
  }
}

async function build(
  gpu: Gpu,
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  isDisposed: () => boolean,
  markDisposed: () => void,
): Promise<HarbourRenderer> {
  const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", label: "harbour"})
  stage.resize([size[0], size[1]])

  const parts = prepareShader(partsWgsl, "harbour_parts.wgsl")
  const water = prepareShader(waterWgsl, "harbour_water.wgsl")
  const shadow = prepareShader(shadowWgsl, "harbour_shadow.wgsl")
  const presentShader = prepareShader(presentWgsl, "harbour_present.wgsl")

  // The islands and buildings never move: one instance at the origin. Its style
  // is the castle's banner colour.
  const style = {style: {format: "float32x4", default: [0, 0, 0, 0]}} as const
  const land = instances({capacity: 1, attributes: style})
  land.add({style: [...linearColor("#d8453a"), 0]})
  const fleet = instances({capacity: MAX_SHIPS, attributes: style})
  const smoke = instances({capacity: PUFFS.forge + PUFFS.inn, attributes: style})
  const puffIds = Array.from({length: PUFFS.forge + PUFFS.inn}, (_, index) => smoke.add({style: [0, 0, 0, index]}))

  const bridges = [
    instanceGeometry(gpu, land, {mesh: meshGeometry(gpu, harbourMesh(), "harbour.land")}),
    instanceGeometry(gpu, fleet, {mesh: meshGeometry(gpu, shipMesh(), "harbour.ship")}),
    instanceGeometry(gpu, smoke, {mesh: meshGeometry(gpu, puffMesh(), "harbour.smoke")}),
  ]

  const camera: {pose: Pose; projection: Float32Array; matrices: CameraMatrices} = {
    pose: {position: new Float32Array(3), quaternion: new Float32Array(4)},
    projection: new Float32Array(16),
    matrices: {view: new Float32Array(16), viewProjection: new Float32Array(16)},
  }
  // A true isometric view: from the corner of a cube, looking at the middle of the harbour.
  rigPose(orbitRig({target: [0, 0, 0], yaw: Math.PI / 4, pitch: Math.atan(Math.SQRT1_2), distance: 40}), camera.pose)
  const cameraValues = {viewProjection: camera.matrices.viewProjection, toEye: normalize([1, 1, 1])}
  const cameraUniforms = uniforms(gpu, cameraValues)

  const islandRows = new Float32Array(ISLANDS.length * 4)
  ISLANDS.forEach((island, index) => islandRows.set([island.x, island.z, island.radius, 0], index * 4))
  const shipRows = new Float32Array(MAX_SHIPS * 4)
  const sceneValues = {
    lightViewProjection: new Float32Array(16),
    sunDirection: [...DAY.sun],
    time: STILL_TIME,
    sunColor: [...DAY.sunColor],
    night: 0,
    skyColor: [...DAY.sky],
    shipCount: 0,
    haze: [0.9, 0.89, 0.82],
    exposure: DAY.exposure,
    islands: rows(islandRows),
    ships: rows(shipRows),
  }
  const sceneUniforms = uniforms(gpu, sceneValues)

  const shadowTarget = target(gpu, {size: [SHADOW_SIZE, SHADOW_SIZE], format: "r8unorm", depth: "depth32float", label: "harbour.sun"})
  const sceneTarget = target(gpu, {size: [size[0], size[1]], format: "rgba8unorm", depth: true, msaa: true, label: "harbour.scene"})
  const shadowSampler = sampler(gpu, {
    compare: "less-equal",
    minFilter: "linear",
    magFilter: "linear",
    addressModeU: "clamp-to-edge",
    addressModeV: "clamp-to-edge",
  })
  const lit = {camera: cameraUniforms, scene: sceneUniforms, shadowMap: shadowTarget, shadowSampler}

  const passes = bridges.map((bridge, index) => ({
    bridge,
    shadow: draw(gpu, {
      shader: shadow,
      geometry: bridge.geometry,
      targets: [shadowTarget],
      writeMask: [],
      depth: {bias: 2, biasSlopeScale: 2.5},
      cull: "none",
      set: {scene: sceneUniforms},
      label: `harbour.shadow.${index}`,
    }),
    color: draw(gpu, {shader: parts, geometry: bridge.geometry, targets: [sceneTarget], cull: "none", set: lit, label: `harbour.parts.${index}`}),
  }))
  const sea = draw(gpu, {shader: water, geometry: seaGeometry(gpu), targets: [sceneTarget], cull: "none", set: lit, label: "harbour.sea"})
  const presentValues = {resolution: [size[0], size[1]], vignette: 0.14}
  const present = effect(gpu, presentShader, {
    set: {present: presentValues, sceneColor: sceneTarget, linearSampler: sampler(gpu, {minFilter: "linear", magFilter: "linear"})},
    label: "harbour.present",
  })
  await Promise.all([...passes.flatMap(pass => [pass.shadow.compile(shadowTarget), pass.color.compile(sceneTarget)]), sea.compile(sceneTarget), present.compile(stage)])

  let ships: Ship[] = []
  const shipIds = new Map<string, InstanceId>()
  let time = STILL_TIME
  let night = 0
  let nightGoal = 0
  let calm = false
  let lastStep: number | undefined
  let clear: [number, number, number, number] = [0.9, 0.89, 0.82, 1]
  const world = new Float32Array(16)

  const fitCamera = () => {
    const [width, height] = stage.size
    const aspect = width / height
    const identity = new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    viewMatrices(camera.pose, identity, camera.matrices)
    const view = camera.matrices.view
    let [left, right, bottom, top] = [Infinity, -Infinity, Infinity, -Infinity]
    const reach = (x: number, y: number, z: number) => {
      const vx = view[0]! * x + view[4]! * y + view[8]! * z + view[12]!
      const vy = view[1]! * x + view[5]! * y + view[9]! * z + view[13]!
      left = Math.min(left, vx)
      right = Math.max(right, vx)
      bottom = Math.min(bottom, vy)
      top = Math.max(top, vy)
    }
    for (const island of Object.values(PLACES)) {
      reach(island.x, 2.4, island.z)
      for (let i = 0; i < 16; i++) {
        const angle = (i / 16) * Math.PI * 2
        reach(island.x + Math.cos(angle) * (island.radius + 1.9), 0, island.z + Math.sin(angle) * (island.radius + 1.9))
      }
    }
    for (const islet of ISLETS) reach(islet.x, 0, islet.z)
    // A narrow frame crops the outer rings a little rather than shrinking the harbour.
    const crop = aspect < 1.3 ? 0.84 : 1
    const middleX = (left + right) / 2
    const middleY = (bottom + top) / 2
    let halfWidth = ((right - left) / 2) * crop * 1.03
    let halfHeight = ((top - bottom) / 2) * 1.06
    if (halfWidth / halfHeight > aspect) halfHeight = halfWidth / aspect
    else halfWidth = halfHeight * aspect
    orthographic(
      {left: middleX - halfWidth, right: middleX + halfWidth, bottom: middleY - halfHeight, top: middleY + halfHeight, near: 1, far: 90},
      camera.projection,
    )
    viewMatrices(camera.pose, camera.projection, camera.matrices)
    cameraUniforms.set(cameraValues)
  }

  const light = () => {
    const sun = normalize(mix3(DAY.sun, NIGHT.sun, night))
    sceneValues.sunDirection = sun
    sceneValues.sunColor = mix3(DAY.sunColor, NIGHT.sunColor, night)
    sceneValues.skyColor = mix3(DAY.sky, NIGHT.sky, night)
    sceneValues.exposure = DAY.exposure + (NIGHT.exposure - DAY.exposure) * night
    sceneValues.night = night
    sceneValues.lightViewProjection.set(sunViewProjection(sun))
  }

  const placeShips = () => {
    let row = 0
    for (const ship of ships) {
      const id = shipIds.get(ship.id)!
      fleet.setWorld(id, shipWorld(ship, time, world))
      shipRows.set([ship.x, ship.z, ship.heading, Math.min(1, ship.speed / CRUISE_SPEED)], row * 4)
      row += 1
    }
    sceneValues.shipCount = row
  }

  const placeSmoke = () => {
    puffIds.forEach((id, index) => {
      const fromForge = index < PUFFS.forge
      const count = fromForge ? PUFFS.forge : PUFFS.inn
      const slot = fromForge ? index : index - PUFFS.forge
      const [x, y, z] = fromForge ? FORGE_SMOKE : INN_SMOKE
      const age = fract(time * (fromForge ? 0.16 : 0.12) + slot / count)
      const size = (fromForge ? 0.07 + 0.2 * age : 0.05 + 0.12 * age) * (1 - smoothstep(0.7, 1, age))
      const drift = Math.sin(time * 0.7 + slot * 2.1) * 0.06 * age
      world.fill(0)
      world[0] = size
      world[5] = size
      world[10] = size
      world[12] = x + age * 0.75 + drift
      world[13] = y + age * (fromForge ? 1.5 : 1.0)
      world[14] = z - age * 0.45 + drift
      world[15] = 1
      smoke.setWorld(id, world)
    })
  }

  const renderer: HarbourRenderer = {
    setAgents(agents) {
      const next = syncFleet(ships, agents)
      for (const ship of ships) {
        if (next.includes(ship)) continue
        fleet.remove(shipIds.get(ship.id)!)
        shipIds.delete(ship.id)
      }
      next.forEach((ship, index) => {
        const colour = [...linearColor(ship.color), index * 1.37] as const
        const id = shipIds.get(ship.id)
        if (id === undefined) shipIds.set(ship.id, fleet.add({style: colour}))
        else fleet.set(id, {style: colour})
      })
      ships = next
      if (calm) parkFleet(ships)
    },
    setLook(look) {
      nightGoal = look.night ? 1 : 0
      const haze = displayColor(look.haze)
      sceneValues.haze = haze
      clear = [haze[0], haze[1], haze[2], 1]
      if (calm || lastStep === undefined) {
        night = nightGoal
        light()
      }
    },
    setCalm(next) {
      calm = next
      if (!calm) return
      time = STILL_TIME
      night = nightGoal
      light()
      parkFleet(ships)
    },
    resize(width, height) {
      stage.resize([width, height])
      sceneTarget.resize([width, height])
      presentValues.resolution = [width, height]
      present.set({present: presentValues})
      fitCamera()
    },
    step() {
      if (calm) return false
      const now = performance.now() / 1000
      const dt = lastStep === undefined ? 0 : Math.min(MAX_STEP, now - lastStep)
      lastStep = now
      time += dt
      stepFleet(ships, dt)
      if (night !== nightGoal) {
        night += (nightGoal - night) * Math.min(1, dt * 2.5)
        if (Math.abs(night - nightGoal) < 0.002) night = nightGoal
        light()
      }
      return true
    },
    present() {
      sceneValues.time = time
      placeShips()
      placeSmoke()
      sceneUniforms.set(sceneValues)
      const counts = passes.map(pass => pass.bridge.publish())
      presentValues.vignette = 0.1 + 0.16 * night
      present.set({present: presentValues})
      frame(gpu, current => {
        current.pass({target: shadowTarget, clear: [0, 0, 0, 0]}, pass => {
          passes.forEach((each, index) => {
            if (counts[index]! > 0) pass.draw(each.shadow, {instances: counts[index]})
          })
        })
        current.pass({target: sceneTarget, clear}, pass => {
          passes.forEach((each, index) => {
            if (counts[index]! > 0) pass.draw(each.color, {instances: counts[index]})
          })
          pass.draw(sea)
        })
        current.pass(stage, present)
      })
    },
    settled() {
      return gpu.settled()
    },
    dispose() {
      if (isDisposed()) return
      markDisposed()
      for (const bridge of bridges) bridge.destroy()
      stage.dispose()
      gpu.dispose()
    },
  }

  fitCamera()
  light()
  return renderer
}

function meshGeometry(gpu: Gpu, vertices: Float32Array<ArrayBuffer>, label: string): Geometry {
  return geometry(gpu, {
    buffers: [
      {
        data: vertices,
        stride: VERTEX_FLOATS * 4,
        attributes: {
          position: {format: "float32x3", offset: 0, location: 0},
          material: {format: "float32", offset: 12, location: 1},
          sway: {format: "float32", offset: 16, location: 2},
        },
      },
    ],
    vertexCount: vertices.length / VERTEX_FLOATS,
    label,
  })
}

/** A square of sea, centred on the harbour, flat until the shader lifts it. */
function seaGeometry(gpu: Gpu): Geometry {
  const side = SEA_SEGMENTS + 1
  const positions = new Float32Array(side * side * 3)
  for (let row = 0; row < side; row++) {
    for (let column = 0; column < side; column++) {
      const at = (row * side + column) * 3
      positions[at] = (column / SEA_SEGMENTS - 0.5) * SEA_SIZE
      positions[at + 2] = (row / SEA_SEGMENTS - 0.5) * SEA_SIZE
    }
  }
  const indices = new Uint32Array(SEA_SEGMENTS * SEA_SEGMENTS * 6)
  let at = 0
  for (let row = 0; row < SEA_SEGMENTS; row++) {
    for (let column = 0; column < SEA_SEGMENTS; column++) {
      const a = row * side + column
      indices.set([a, a + side, a + 1, a + 1, a + side, a + side + 1], at)
      at += 6
    }
  }
  return geometry(gpu, {
    buffers: [{data: positions, stride: 12, attributes: {position: {format: "float32x3", offset: 0, location: 0}}}],
    indices,
    label: "harbour.sea",
  })
}

/** A ship riding the wave under it: pitched by the swell, heeled into its turn. */
function shipWorld(ship: Ship, time: number, out: Float32Array): Float32Array {
  const fx = Math.cos(ship.heading)
  const fz = Math.sin(ship.heading)
  const y = waveHeight(ship.x, ship.z, time)
  const along = (waveHeight(ship.x + fx * 0.3, ship.z + fz * 0.3, time) - waveHeight(ship.x - fx * 0.3, ship.z - fz * 0.3, time)) / 0.6
  const across = (waveHeight(ship.x - fz * 0.2, ship.z + fx * 0.2, time) - waveHeight(ship.x + fz * 0.2, ship.z - fx * 0.2, time)) / 0.4
  const pitch = Math.atan(along) * 0.9
  const roll = Math.atan(across) * 0.9 - ship.turn * ship.speed * 0.5
  // Bow along heading, mast up, beam across; then pitch about the beam and roll about the keel.
  let forward = [fx, 0, fz]
  let up = [0, 1, 0]
  let beam = [-fz, 0, fx]
  ;[forward, up] = [add(scale(forward, Math.cos(pitch)), scale(up, Math.sin(pitch))), add(scale(up, Math.cos(pitch)), scale(forward, -Math.sin(pitch)))]
  ;[up, beam] = [add(scale(up, Math.cos(roll)), scale(beam, Math.sin(roll))), add(scale(beam, Math.cos(roll)), scale(up, -Math.sin(roll)))]
  out.set([...scale(forward, SHIP_SCALE), 0, ...scale(up, SHIP_SCALE), 0, ...scale(beam, SHIP_SCALE), 0, ship.x, y, ship.z, 1])
  return out
}

/** The sun's orthographic view over the whole harbour. */
function sunViewProjection(sun: readonly number[]): Float32Array {
  const distance = 30
  const node = group({position: [sun[0]! * distance, sun[1]! * distance, sun[2]! * distance]}).lookAt([0, 0, 0])
  const pose: Pose = {position: new Float32Array(node.worldPosition), quaternion: new Float32Array(node.quaternion)}
  const reach = 12.5
  const projection = orthographic(
    {left: -reach, right: reach, bottom: -reach, top: reach, near: distance - 16, far: distance + 16},
    new Float32Array(16),
  )
  const matrices: CameraMatrices = {view: new Float32Array(16), viewProjection: new Float32Array(16)}
  viewMatrices(pose, projection, matrices)
  return matrices.viewProjection
}

/** Views onto a packed array, one per vec4 row of a uniform array. */
function rows(packed: Float32Array): Float32Array[] {
  return Array.from({length: packed.length / 4}, (_, index) => packed.subarray(index * 4, index * 4 + 4))
}

function hexChannels(hex: string): [number, number, number] {
  const value = Number.parseInt(hex.slice(1), 16)
  return [((value >> 16) & 255) / 255, ((value >> 8) & 255) / 255, (value & 255) / 255]
}

/** #rrggbb as linear light, for colours the shader lights. */
function linearColor(hex: string): [number, number, number] {
  const [r, g, b] = hexChannels(hex)
  return [r ** 2.2, g ** 2.2, b ** 2.2]
}

/** #rrggbb as the page shows it, for colours mixed after tone mapping. */
function displayColor(hex: string): [number, number, number] {
  return hexChannels(hex)
}

function normalize(vector: readonly number[]): [number, number, number] {
  const length = Math.hypot(vector[0]!, vector[1]!, vector[2]!)
  return [vector[0]! / length, vector[1]! / length, vector[2]! / length]
}

function mix3(a: readonly number[], b: readonly number[], t: number): [number, number, number] {
  return [a[0]! + (b[0]! - a[0]!) * t, a[1]! + (b[1]! - a[1]!) * t, a[2]! + (b[2]! - a[2]!) * t]
}

function scale(vector: readonly number[], by: number): number[] {
  return vector.map(value => value * by)
}

function add(a: readonly number[], b: readonly number[]): number[] {
  return a.map((value, index) => value + b[index]!)
}

function fract(value: number): number {
  return value - Math.floor(value)
}

function smoothstep(edge0: number, edge1: number, value: number): number {
  const t = Math.min(1, Math.max(0, (value - edge0) / (edge1 - edge0)))
  return t * t * (3 - 2 * t)
}
