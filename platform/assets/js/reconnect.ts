// How long the live connection waits before each try to reconnect, and a page
// before each try to rejoin. Each wait is drawn between half and all of its step,
// so the pages a stopping machine closes together come back spread out instead
// of in the same few milliseconds, each mount reading from the same small pool
// (the endpoint's drainer). The first reconnect comes within half a second.
const reconnectSteps = [500, 1000, 2000]
const rejoinSteps = [1000, 2000, 5000]

const jittered = (ms: number): number => ms / 2 + Math.random() * (ms / 2)

export const reconnectAfterMs = (tries: number): number => jittered(reconnectSteps[tries - 1] ?? 5000)

export const rejoinAfterMs = (tries: number): number => jittered(rejoinSteps[tries - 1] ?? 10000)
