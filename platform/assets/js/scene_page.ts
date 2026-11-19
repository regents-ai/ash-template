/**
 * A scene's own page (`AshTemplateWeb.SceneHTML`): its one stage, run by the same
 * viewer as the Splats and Scenes pages (`hooks/splat_island.ts`), with no live
 * connection, and the feedback tool offered to a browser agent. Built on its own as
 * one classic script with its stylesheet (`../css/scene_page.css`), so a frame
 * sandboxed with scripts allowed, whose origin is no site's, loads them without asking
 * this site's leave.
 */
import "../css/scene_page.css"
import {offerFeedbackTool} from "./feedback_tool"
import {createSplatIsland} from "./hooks/splat_island"

offerFeedbackTool()
createSplatIsland(document.querySelector<HTMLElement>("[data-splats-file]")!).mount()
