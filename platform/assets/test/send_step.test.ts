// Invariant: the send step compares addresses in any letter case without viem,
// so a wallet that answers its account checksummed still sends the server's step,
// and a wallet on another account sends nothing.
import {expect, it} from "vitest"

import {failure, NothingSent, sendStep, type TransactionStep} from "../js/wallet_actions/send_step"

const chain = {chain_id: 8453, name: "Base", rpc_url: "https://mainnet.base.org"}
const step: TransactionStep = {
  kind: "transaction",
  step: "buy",
  to: "0x1111111111111111111111111111111111111111",
  data: "0x",
  value: "0x0",
}
const hash = `0x${"ab".repeat(32)}`

function walletOn(account: string) {
  const sent: unknown[] = []
  const provider = {
    request: async ({method, params}: {method: string; params?: unknown[]}) => {
      if (method === "eth_chainId") return "0x2105"
      if (method === "eth_accounts") return [account]
      if (method === "eth_sendTransaction") {
        sent.push(params?.[0])
        return hash
      }
      throw new Error(`unexpected ${method}`)
    },
  }
  return {sent, selected: {address: account, provider}}
}

it("sends when the wallet names the signer in other letter case", async () => {
  const checksummed = "0xAbCdEf0123456789aBcDeF0123456789AbCdEf01"
  const signer = checksummed.toLowerCase() as `0x${string}`
  const {sent, selected} = walletOn(checksummed)

  await expect(sendStep(chain, signer, step, () => selected, () => undefined)).resolves.toBe(hash)
  expect(sent).toEqual([{from: signer, to: step.to, data: "0x", value: "0x0", chainId: "0x2105"}])
})

it("sends nothing when the wallet answers for another account", async () => {
  const {sent, selected} = walletOn("0x2222222222222222222222222222222222222222")
  const signer = "0x3333333333333333333333333333333333333333"

  await expect(sendStep(chain, signer, step, () => selected, () => undefined)).rejects.toBeInstanceOf(NothingSent)
  expect(sent).toEqual([])
})

// Invariant: a press that ends without an answer is named for what the wallet may
// have done. Before the wallet was asked, nothing was sent; after, an unexplained
// end may have sent the transaction or, for a signature step, made the signature,
// and the two are never confused, since the page tells the person which to check.
it("names an unexplained end by the kind of step the wallet was asked for", () => {
  const dropped = new Error("the wallet stopped answering")

  expect(failure(true, dropped, false)).toBe("send_unconfirmed")
  expect(failure(true, dropped, true)).toBe("sign_unconfirmed")
  for (const signature of [false, true]) {
    expect(failure(true, {code: 4001}, signature)).toBe("wallet_declined")
    expect(failure(false, dropped, signature)).toBe("wallet_unavailable")
    expect(failure(false, new NothingSent("network_mismatch"), signature)).toBe("network_mismatch")
  }
})
