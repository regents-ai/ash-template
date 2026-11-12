/**
 * The hooks only the lab pages at /animations/* use, loaded on those pages only.
 * Datascape is not here: the homepage uses it too, so app.ts registers it everywhere.
 */
import {Crown} from "./hooks/crown"
import {CodeCube} from "./hooks/code_cube"
import {Harbour} from "./hooks/harbour"
import {KeyfleetField, KeyfleetKeyCard, KeyfleetReplay} from "./hooks/keyfleet_hero"
import {SwarmCity} from "./hooks/swarm_city"
import {TwinCube} from "./hooks/twin_cube"
import {ValueCard} from "./hooks/value_card"
import {Wonder} from "./hooks/wonder"
import {WorldCube} from "./hooks/world_cube"

export const hooks = {Crown, CodeCube, Harbour, KeyfleetField, KeyfleetKeyCard, KeyfleetReplay, SwarmCity, TwinCube, ValueCard, Wonder, WorldCube}
