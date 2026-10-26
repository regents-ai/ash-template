/** The hooks only the lab pages at /animations/* use, loaded on those pages only. */
import {Crown} from "./hooks/crown"
import {CodeCube} from "./hooks/code_cube"
import {Harbour} from "./hooks/harbour"
import {KeyfleetField, KeyfleetKeyCard, KeyfleetReplay} from "./hooks/keyfleet_hero"
import {SwarmCity} from "./hooks/swarm_city"
import {TwinCube} from "./hooks/twin_cube"
import {Wonder} from "./hooks/wonder"

export const hooks = {Crown, CodeCube, Harbour, KeyfleetField, KeyfleetKeyCard, KeyfleetReplay, SwarmCity, TwinCube, Wonder}
