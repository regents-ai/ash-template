defmodule AshTemplate.ChainClient do
  @moduledoc """
  JSON-RPC reads at the latest block of the chain a review names.

  `RegentChain.Outcome` reads sent steps through `transaction/2` and `receipt/2`.
  Every read is at `latest`: never count confirmations and never wait for `safe`
  or `finalized`. The RPC address comes from the server-built review, never from
  the browser.
  """

  @doc "The transaction sent as `hash`, or `nil` while the chain does not know it."
  def transaction(chain, hash), do: rpc(chain, "eth_getTransactionByHash", [hash])

  @doc "The receipt for `hash`, or `nil` while it has not landed."
  def receipt(chain, hash), do: rpc(chain, "eth_getTransactionReceipt", [hash])

  @doc "The native balance of `address` in wei."
  def balance(chain, address) do
    with {:ok, "0x" <> hex} <- rpc(chain, "eth_getBalance", [address, "latest"]) do
      {:ok, String.to_integer(hex, 16)}
    end
  end

  @doc "One JSON-RPC request to the chain's node."
  def rpc(%{rpc_url: url}, method, params) do
    case Req.post(url,
           json: %{jsonrpc: "2.0", id: 1, method: method, params: params},
           retry: false,
           receive_timeout: 5_000
         ) do
      {:ok, %{status: 200, body: %{"result" => result}}} -> {:ok, result}
      {:ok, %{body: %{"error" => error}}} -> {:error, {:rpc, error}}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, error} -> {:error, error}
    end
  end
end
