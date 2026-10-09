defmodule AshTemplate.Limits do
  @moduledoc """
  The named allowances in `config :ash_template, :limits`, each spent through
  `AshTemplate.Accounts.RequestRateLimiter`.
  """

  alias AshTemplate.Accounts.RequestRateLimiter
  alias AshTemplate.Actors.{Agent, Human}

  @doc "Spends one of `name`'s allowance for `who`: `:ok` or `:limited`."
  @spec spend(atom(), term()) :: :ok | :limited
  def spend(name, who) do
    config = :ash_template |> Application.fetch_env!(:limits) |> Keyword.fetch!(name)

    case RequestRateLimiter.admit({name, who}, config[:limit], config[:window_seconds]) do
      {:ok, _budget} -> :ok
      {:error, :rate_limited, _budget} -> :limited
    end
  end

  @doc "Who an actor's writing counts against: the person, or the agent."
  def writer(%Human{human_account_id: id}), do: {:human, id}
  def writer(%Agent{pairing: :active, human_account_id: id}), do: {:human, id}
  def writer(%Agent{agent_id: id}), do: {:agent, id}
end
