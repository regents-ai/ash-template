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
    case spend_until(name, who) do
      :ok -> :ok
      {:limited, _seconds} -> :limited
    end
  end

  @doc "As `spend/2`, saying when limited how many seconds are left of the window."
  @spec spend_until(atom(), term()) :: :ok | {:limited, pos_integer()}
  def spend_until(name, who) do
    config = allowance(name)

    case RequestRateLimiter.admit({name, who}, config[:limit], config[:window_seconds]) do
      {:ok, _budget} -> :ok
      {:error, :rate_limited, budget} -> {:limited, budget.reset}
    end
  end

  @doc "`name`'s allowance: its `limit` each `window_seconds`, as configured."
  @spec allowance(atom()) :: [limit: pos_integer(), window_seconds: pos_integer()]
  def allowance(name),
    do: :ash_template |> Application.fetch_env!(:limits) |> Keyword.fetch!(name)

  @doc "Who an actor's writing counts against: the person, or the agent."
  def writer(%Human{human_account_id: id}), do: {:human, id}
  def writer(%Agent{pairing: :active, human_account_id: id}), do: {:human, id}
  def writer(%Agent{agent_id: id}), do: {:agent, id}
end
