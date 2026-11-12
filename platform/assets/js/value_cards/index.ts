/** Every value card's panel, by the name its card carries in `data-value-card`. */
import {actions} from "./panels/actions"
import {assemble} from "./panels/assemble"
import {ballot} from "./panels/ballot"
import {bench} from "./panels/bench"
import {blob} from "./panels/blob"
import {board} from "./panels/board"
import {call} from "./panels/call"
import {chevron} from "./panels/chevron"
import {circuit} from "./panels/circuit"
import {climb} from "./panels/climb"
import {coin} from "./panels/coin"
import {columns} from "./panels/columns"
import {commits} from "./panels/commits"
import {compare} from "./panels/compare"
import {cover} from "./panels/cover"
import {fleet} from "./panels/fleet"
import {freeze} from "./panels/freeze"
import {gather} from "./panels/gather"
import {glitch} from "./panels/glitch"
import {heal} from "./panels/heal"
import {learn} from "./panels/learn"
import {level} from "./panels/level"
import {link} from "./panels/link"
import {notebook} from "./panels/notebook"
import {payoff} from "./panels/payoff"
import {pinch} from "./panels/pinch"
import {prorata} from "./panels/prorata"
import {radar} from "./panels/radar"
import {rain} from "./panels/rain"
import {rewrite} from "./panels/rewrite"
import {ripple} from "./panels/ripple"
import {rooms} from "./panels/rooms"
import {sandbox} from "./panels/sandbox"
import {scan} from "./panels/scan"
import {scope} from "./panels/scope"
import {score} from "./panels/score"
import {seal} from "./panels/seal"
import {seam} from "./panels/seam"
import {seats} from "./panels/seats"
import {shard} from "./panels/shard"
import {spokes} from "./panels/spokes"
import {streams} from "./panels/streams"
import {tools} from "./panels/tools"
import {weave} from "./panels/weave"
import type {ValuePanel} from "./panel"

export const panels: Record<string, ValuePanel> = {
  level,
  payoff,
  seam,
  columns,
  rain,
  gather,
  chevron,
  compare,
  climb,
  seal,
  scan,
  ripple,
  assemble,
  link,
  freeze,
  actions,
  score,
  learn,
  glitch,
  blob,
  pinch,
  heal,
  bench,
  radar,
  seats,
  fleet,
  ballot,
  spokes,
  shard,
  rooms,
  board,
  weave,
  commits,
  notebook,
  rewrite,
  circuit,
  cover,
  sandbox,
  prorata,
  streams,
  coin,
  tools,
  call,
  scope,
}
