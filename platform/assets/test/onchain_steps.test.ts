import {expect, it} from "vitest"

import {answers, type Answer, type Settled} from "../js/hooks/onchain_steps"

// The wallet's answers on their way to a server the page reaches or not: each
// push waits until the test says whether the server heard it.
function line() {
  const pushes: {answer: Answer; heard: (heard: boolean) => void; failed: () => void}[] = []
  const ends: [number, Settled][] = []
  const sent = answers(
    answer =>
      new Promise<boolean>((resolve, reject) =>
        pushes.push({answer, heard: resolve, failed: () => reject(new Error("push failed"))}),
      ),
    (answer, end) => ends.push([answer.during, end]),
  )
  return {sent, pushes, ends}
}

const answer = (during: number): Answer => ({event: "step_sent", payload: {step: "record"}, during})
const settle = () => new Promise(resolve => setImmediate(resolve))

it("passes an answer the server hears once, with nothing to say", async () => {
  const {sent, pushes, ends} = line()
  sent.pass(answer(1))
  pushes[0].heard(true)
  await settle()

  expect(pushes).toHaveLength(1)
  expect(ends).toEqual([])
})

it("keeps an answer the page could not send and passes it once more when the page joins again", async () => {
  const {sent, pushes, ends} = line()
  sent.pass(answer(1))
  pushes[0].heard(false)
  await settle()
  expect(ends).toEqual([[1, "kept"]])

  sent.rejoined()
  expect(pushes.map(push => push.answer)).toEqual([answer(1), answer(1)])
  pushes[1].heard(true)
  await settle()

  expect(ends).toEqual([
    [1, "kept"],
    [1, "delivered"],
  ])
})

it("lets an answer go when the server does not hear it after the page joins again either", async () => {
  const {sent, pushes, ends} = line()
  sent.pass(answer(1))
  pushes[0].heard(false)
  await settle()
  sent.rejoined()
  pushes[1].heard(false)
  await settle()
  sent.rejoined()

  expect(pushes).toHaveLength(2)
  expect(ends).toEqual([
    [1, "kept"],
    [1, "lost"],
  ])
})

it("sends an answer once more at once when the page joined again while it was on its way", async () => {
  const {sent, pushes, ends} = line()
  sent.pass(answer(1))
  sent.rejoined()
  pushes[0].heard(false)
  await settle()
  expect(pushes).toHaveLength(2)
  expect(ends).toEqual([])

  pushes[1].heard(true)
  await settle()
  expect(ends).toEqual([[1, "delivered"]])
})

it("passes kept answers on in the order the wallet gave them", async () => {
  const {sent, pushes} = line()
  sent.pass(answer(1))
  sent.pass(answer(2))
  pushes[0].heard(false)
  pushes[1].heard(false)
  await settle()
  sent.rejoined()

  expect(pushes.slice(2).map(push => push.answer.during)).toEqual([1, 2])
})

it("takes a push that failed outright as one the server did not hear", async () => {
  const {sent, pushes, ends} = line()
  sent.pass(answer(1))
  pushes[0].failed()
  await settle()

  expect(ends).toEqual([[1, "kept"]])
})

it("lets every kept answer go when the page is left, and keeps none after", async () => {
  const {sent, pushes, ends} = line()
  sent.pass(answer(1))
  pushes[0].heard(false)
  await settle()
  sent.gone()
  sent.pass(answer(2))
  pushes[1].heard(false)
  await settle()
  sent.rejoined()

  expect(pushes).toHaveLength(2)
  expect(ends).toEqual([
    [1, "kept"],
    [1, "lost"],
    [2, "lost"],
  ])
})

// Every run of up to five things the connection and the server can do to one
// answer: it is pushed at most twice, ends at most once, and is lost only if the
// server never heard it.
it("pushes an answer at most twice and ends it at most once, whatever the connection does", async () => {
  const moves = ["heard", "missed", "failed", "rejoined", "gone"] as const
  const runs: (typeof moves)[number][][] = [[]]
  for (let length = 0; length < 5; length += 1)
    for (const run of runs.filter(run => run.length === length)) for (const move of moves) runs.push([...run, move])

  for (const run of runs) {
    const {sent, pushes, ends} = line()
    let next = 0
    let heard = false
    sent.pass(answer(1))
    for (const move of run) {
      if (move === "rejoined") sent.rejoined()
      else if (move === "gone") sent.gone()
      else if (next < pushes.length) {
        const push = pushes[next++]
        if (move === "heard") heard = true
        if (move === "failed") push.failed()
        else push.heard(move === "heard")
      }
      await settle()
    }

    const endings = ends.filter(([, end]) => end !== "kept")
    expect(pushes.length, run.join(" ")).toBeLessThanOrEqual(2)
    expect(endings.length, run.join(" ")).toBeLessThanOrEqual(1)
    if (heard) expect(endings.map(([, end]) => end), run.join(" ")).not.toContain("lost")
    else expect(endings.map(([, end]) => end), run.join(" ")).not.toContain("delivered")
  }
})
