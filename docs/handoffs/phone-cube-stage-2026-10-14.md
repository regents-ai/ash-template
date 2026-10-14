# Phone cube stage — local adoption handoff

Authority: Sean’s 14 October decision RG-PHONE-STAGE, relayed by the orchestrator: template first, then Regents. Local implementation only; no deployment. Money tests and Points earning remain off.

Design check: CSS Grid owns layout, existing ResizeObserver owns canvas sizing, existing Anime.js hooks own motion. No new JavaScript, storage, jobs or timers.

| Before | After | Why |
| --- | --- | --- |
| 46rem stage, 53rem on the narrowest phones | clamp(32rem, 72svh, 38rem) below 48rem | Remove space reserved for the full fallback list |
| Full fallback list sets minimum stage height | List scrolls within the same fixed stage | Retain every link without resizing when the renderer starts |
| Desktop sizing | Unchanged | Keep the existing composition |

Changed source: platform/assets/css/components/world_cube.css. No shared design-system primitive changed; this is the template-owned cube composition.

Local verification on localhost:4060: asset build and whitespace checks passed. /animations/cube at 320×740: actual renderer ready, stage 532.8px, document width 320px; keyboard focus on the last world link stays inside the stage. At 390×844: stage 607.7px and document width 390px. At 1280×900: existing desktop stage 648px and document width 1280px. /animations/twin-cube at 320×740: world bottom and code top both 819.8px, no horizontal overflow. Entered a room and used Leave this room successfully. No new behavioral tests.

Fallback verified using a temporary copy of the rendered twin-cube HTML with scripts removed and the actual application stylesheet. At 320×740 the stage remained 532.8px, matching the rendered cube; the list had 485px visible height and 984px scroll height. Tab reached all six links in order, scrolling the list from 0 to 499px; the final focused link was fully visible. Document width remained 320px. The temporary preview server was stopped and no fixture is included in the commit.

Limits: no measured startup layout-shift trace, physical-phone browser chrome test, runtime GPU-loss recovery, or production verification. Separate ready/fallback states have identical stage heights; do not represent this as a measured transition trace.

## Regents adoption

Copy the template CSS change first. Regents also owns a separate parent-grid reservation in platform/assets/css/pages/home.css; copying component CSS alone cannot remove that empty band. Its phone .rl-hero--home uses --rl-worlds-height values 75rem, 54.5rem and 44rem, and its world cube spans the heading and second row through subgrid. Below 48rem, put the heading, world cube and code cube in separate natural rows; place the world cube in row 2, use its own minmax(0, 1fr) row instead of subgrid, and clear the fallback list’s forced grid-row:2. Let the bounded component height determine that row. Keep desktop overrides at 48rem and above. Verify the actual Regents heading and both ready/fallback layouts before committing its adoption. This handoff does not claim Regents is fixed or authorize deployment.
