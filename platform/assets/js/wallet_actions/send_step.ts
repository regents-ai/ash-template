import type {Address, Hash, Hex} from "viem"

import type {EthereumProvider, SelectedWallet} from "./connected_wallet"

/**
 * The chain a step goes to. The server's review also names it and its public
 * node; the wallet takes those from Privy's own list of networks instead.
 */
export type StepChain = {chain_id: number}

/** One transaction a button sends, built on the server. */
export type TransactionStep = {kind: "transaction"; step: string; to: Address; data: Hex; value: Hex}

/** One EIP-712 signature a button asks for, built on the server. */
export type SignatureStep = {kind: "signature"; step: string; typed_data: Record<string, unknown>}

export type Step = TransactionStep | SignatureStep

/** Nothing reached the wallet's send; the reason picks the words the server shows. */
export class NothingSent extends Error {
  constructor(readonly reason: "step_unknown" | "wallet_unavailable" | "switch_declined" | "network_mismatch") {
    super(reason)
  }
}

export type Failure =
  | NothingSent["reason"]
  | "wallet_declined"
  | "insufficient_funds"
  | "send_unconfirmed"
  | "sign_unconfirmed"

/**
 * Sends one transaction through `wallet`, from the signer the server built the
 * step for. A wallet on another chain is first asked to switch to the step's.
 */
export async function sendStep(
  chain: StepChain,
  signer: Address,
  step: TransactionStep,
  wallet: SelectedWallet,
  sending: () => void,
): Promise<Hash> {
  const provider = await ready(chain, wallet)

  sending()
  const hash = await provider.request({
    method: "eth_sendTransaction",
    params: [{
      from: signer,
      to: step.to,
      data: step.data,
      value: step.value,
      // The step's chain, for a wallet that sends only on the chain it is given.
      chainId: `0x${chain.chain_id.toString(16)}`,
    }],
  })
  if (typeof hash !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(hash)) {
    throw new Error("The wallet did not return a transaction hash.")
  }
  return hash as Hash
}

/**
 * Asks `wallet` to sign the server's typed data as the signer, after the same
 * chain switch as a send. Returns the signature only; the server keeps the
 * typed data it built.
 */
export async function signStep(
  chain: StepChain,
  signer: Address,
  step: SignatureStep,
  wallet: SelectedWallet,
  sending: () => void,
): Promise<Hex> {
  const provider = await ready(chain, wallet)

  sending()
  const signature = await provider.request({
    method: "eth_signTypedData_v4",
    params: [signer, JSON.stringify(step.typed_data)],
  })
  if (typeof signature !== "string" || !/^0x[0-9a-fA-F]{130}$/.test(signature)) {
    throw new Error("The wallet did not return a signature.")
  }
  return signature as Hex
}

/**
 * Why a press ended without a hash or signature. After `sending`, the wallet may
 * have sent the transaction, or made the signature when the step was one
 * (`signature`).
 */
export function failure(sending: boolean, error: unknown, signature: boolean): Failure {
  if (!sending) return error instanceof NothingSent ? error.reason : "wallet_unavailable"
  if (hasCode(error, 4001)) return "wallet_declined"
  // No EIP-1193 code names this; wallets and nodes all say it in these words.
  if (hasMessage(error, /insufficient funds/i)) return "insufficient_funds"
  return signature ? "sign_unconfirmed" : "send_unconfirmed"
}

// A wallet on another chain is asked to switch to the step's on every press,
// through Privy's own switch, and once that switch resolves the press goes on.
// When the wallet declines or fails the switch, this press sends nothing and
// the next press asks again.
async function ready(chain: StepChain, {provider, switchChain}: SelectedWallet): Promise<EthereumProvider> {
  if ((await chainId(provider)) !== chain.chain_id) {
    await switchChain(chain.chain_id).catch((error: unknown) => {
      throw new NothingSent(hasCode(error, 4001) ? "switch_declined" : "network_mismatch")
    })
  }
  return provider
}

/** The chain the wallet is on now; -1 when it does not say. */
async function chainId(provider: EthereumProvider): Promise<number> {
  const value = await provider.request({method: "eth_chainId"})
  return typeof value === "string" && /^0x[0-9a-f]+$/i.test(value) ? Number(BigInt(value)) : -1
}

// Wallets wrap the EIP-1193 error in `cause` chains of their own.
function hasCode(error: unknown, code: number): boolean {
  return causes(error).some(e => (e as {code?: unknown}).code === code)
}

function hasMessage(error: unknown, words: RegExp): boolean {
  return causes(error).some(e => {
    const message = (e as {message?: unknown}).message
    return typeof message === "string" && words.test(message)
  })
}

function causes(error: unknown): object[] {
  const chain: object[] = []
  for (let e = error; e && typeof e === "object" && chain.length < 8; e = (e as {cause?: unknown}).cause) chain.push(e)
  return chain
}
