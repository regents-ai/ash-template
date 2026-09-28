import type {Hook} from "../hook_composition"
import {
  activeEthereumWallet,
  forgetWalletDisconnected,
  replaceActiveEthereumWallet,
  type EthereumProvider,
} from "../wallet_actions/connected_wallet"

type LabHook = Hook & {
  el: HTMLElement
  pushEvent(event: string, payload: unknown): Promise<unknown>
  cleanup?: () => void
}

type RpcError = {code: number; message: string}

/**
 * The workshop's stand-in wallet app. It holds the lab chain's first three
 * accounts, one provider each, and takes Privy's place as the active wallet on
 * this page only. Sends and signatures go through the page to the lab chain;
 * the network, a refused switch, a decline and a slow answer are the tester's to set.
 */
export const OnchainLab: Hook = {
  mounted(this: LabHook) {
    const root = this.el
    const labChainId = Number(root.dataset.labChainId)
    const field = (name: string) => root.querySelector<HTMLInputElement>(`[name="${name}"]:checked`)
    const ticked = (name: string) => field(name) !== null
    const log = (words: string) => {
      const line = root.querySelector<HTMLElement>("[data-lab-log]")
      if (line) line.textContent = words
    }
    let chainId = Number(field("lab-network")?.value ?? labChainId)

    const provider = (address: string): EthereumProvider => ({
      request: async ({method, params = []}) => {
        if (ticked("lab-slow")) await new Promise(resolve => setTimeout(resolve, 1500))
        switch (method) {
          case "eth_chainId":
            return `0x${chainId.toString(16)}`
          case "eth_accounts":
            return [address]
          case "wallet_switchEthereumChain": {
            if (ticked("lab-refuse-switch")) throw rpcError({code: 4001, message: "User rejected the request."})
            const wanted = Number(BigInt((params[0] as {chainId: string}).chainId))
            if (wanted !== labChainId && wanted !== 8453) throw rpcError({code: 4902, message: "Unrecognized chain."})
            chainId = wanted
            root.querySelector<HTMLInputElement>(`[name="lab-network"][value="${wanted}"]`)!.checked = true
            log(`The wallet switched to network ${wanted}.`)
            return null
          }
          case "eth_sendTransaction":
          case "eth_signTypedData_v4": {
            if (ticked("lab-decline")) {
              log("The wallet declined.")
              throw rpcError({code: 4001, message: "User rejected the request."})
            }
            if (chainId !== labChainId) throw rpcError({code: -32603, message: "This wallet can only send on the lab chain."})
            const reply = await this.pushEvent("lab_rpc", {method, params}) as {result?: string; error?: RpcError}
            if (reply.error) throw rpcError(reply.error)
            log(method === "eth_sendTransaction" ? `The wallet sent ${reply.result}.` : "The wallet signed.")
            return reply.result
          }
          default:
            throw rpcError({code: 4200, message: `The lab wallet does not support ${method}.`})
        }
      },
    })

    const providers = new Map(
      [...root.querySelectorAll<HTMLInputElement>('[name="lab-wallet"]')]
        .filter(input => input.value)
        .map(input => [input.value, provider(input.value)]),
    )
    const choose = () => {
      const address = field("lab-wallet")?.value || null
      const wanted = address ? {address, provider: providers.get(address)!} : null
      if (activeEthereumWallet()?.provider === wanted?.provider) return
      if (wanted) forgetWalletDisconnected()
      replaceActiveEthereumWallet(wanted)
      window.dispatchEvent(new CustomEvent("ash:wallet-state"))
    }
    const changed = (event: Event) => {
      const input = event.target as HTMLInputElement
      if (input.name === "lab-network") chainId = Number(input.value)
      if (input.name === "lab-wallet") choose()
    }
    // The page's own Privy bridge may also announce a wallet; the tester's choice stands.
    const reassert = () => choose()

    root.addEventListener("change", changed)
    window.addEventListener("ash:wallet-state", reassert)
    choose()
    this.cleanup = () => {
      root.removeEventListener("change", changed)
      window.removeEventListener("ash:wallet-state", reassert)
      replaceActiveEthereumWallet(null)
    }
  },
  destroyed(this: LabHook) { this.cleanup?.() },
}

function rpcError({code, message}: RpcError): Error & {code: number} {
  return Object.assign(new Error(message), {code})
}
