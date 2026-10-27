import {expect, test} from "./support/test"

// What a page tells search engines and AI answers it holds (Regent.StructuredData),
// read from the rendered head as a crawler reads it: every page carries the site's
// own graph, and a page holding a question adds it, with its marked answer.

type Node = {"@type": string; [key: string]: unknown}

async function graph(page: import("@playwright/test").Page): Promise<Node[]> {
  const scripts = await page.locator('script[type="application/ld+json"]').allTextContents()
  expect(scripts).toHaveLength(1)
  return (JSON.parse(scripts[0]) as {"@graph": Node[]})["@graph"]
}

test("a page holding no question carries only the site's graph", async ({page}) => {
  await page.goto("/docs")
  expect((await graph(page)).map(node => node["@type"])).toEqual(["Organization", "WebSite"])
})

test("a question's page names the question and its marked answer", async ({page}) => {
  await page.goto("/showcase/discussion")
  const nodes = await graph(page)
  expect(nodes.map(node => node["@type"])).toEqual(["Organization", "WebSite", "QAPage"])

  const question = nodes[2].mainEntity as Record<string, any>
  await expect(page.locator("#sample-thread-title")).toContainText(question.name)
  expect(question.answerCount).toBe(await page.locator("#sample-replies .rg-discussion__post").count())
  expect(question.acceptedAnswer.url).toMatch(/\/showcase\/discussion#r2$/)
  expect(question.suggestedAnswer.map((answer: {url: string}) => answer.url)).not.toContain(
    question.acceptedAnswer.url,
  )
})
