/**
 * The hooks only the lab pages at /animations/* use, loaded on those pages only.
 * Datascape is not here: the homepage uses it too, so app.ts registers it everywhere.
 */
import {AskBar} from "./hooks/ask_bar"
import {Crown} from "./hooks/crown"
import {CodeCube} from "./hooks/code_cube"
import {FrostedGlass} from "./hooks/frosted_glass"
import {GlowLight} from "./hooks/glow_light"
import {Harbour} from "./hooks/harbour"
import {KeyfleetField, KeyfleetKeyCard, KeyfleetReplay} from "./hooks/keyfleet_hero"
import {SwarmCity} from "./hooks/swarm_city"
import {TwinCube} from "./hooks/twin_cube"
import {ValueLight} from "./hooks/value_light"
import {Wonder} from "./hooks/wonder"
import {WorldCube} from "./hooks/world_cube"

export const hooks = {AskBar, Crown, CodeCube, FrostedGlass, GlowLight, Harbour, KeyfleetField, KeyfleetKeyCard, KeyfleetReplay, SwarmCity, TwinCube, ValueLight, Wonder, WorldCube}
