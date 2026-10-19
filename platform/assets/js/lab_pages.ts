/** The hooks only the lab pages at /animations/* use, loaded on those pages only. */
import {Crown} from "./hooks/crown"
import {CodeCube} from "./hooks/code_cube"
import {KeyfleetField, KeyfleetKeyCard, KeyfleetReplay} from "./hooks/keyfleet_hero"
import {TwinCube} from "./hooks/twin_cube"
import {WorldCube} from "./hooks/world_cube"

export const hooks = {Crown, CodeCube, KeyfleetField, KeyfleetKeyCard, KeyfleetReplay, TwinCube, WorldCube}
