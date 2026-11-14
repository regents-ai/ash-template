/**
 * Every icon on the icon sheet, by the name the page gives it
 * (`AshTemplateWeb.IconsLabLive`). Thirty-two follow a reference sheet of diagram
 * icons (connect, signals, flow, control); twenty-four say what Regents products do.
 */
import type {IconSet} from "../icon"
import {agents} from "./agents"
import {capital} from "./capital"
import {connect} from "./connect"
import {control} from "./control"
import {fleets} from "./fleets"
import {flow} from "./flow"
import {signals} from "./signals"

export const ICON_GROUPS = {connect, signals, flow, control, agents, capital, fleets} as const

export const ICONS: IconSet = Object.assign({}, ...Object.values(ICON_GROUPS))
