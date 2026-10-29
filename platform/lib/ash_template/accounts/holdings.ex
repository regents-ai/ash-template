defmodule AshTemplate.Accounts.Holdings do
  @moduledoc """
  What a paired agent reads of its person's Credits and Points, or an agent
  that owns its account reads of its own, each one answer every surface gives:
  the HTTP API, the browser tools, regents-cli and the hosted MCP server.
  Nothing is stored here; the figures are the Credits and Points libraries' own.
  """

  use Ash.Resource,
    domain: AshTemplate.Accounts,
    authorizers: [Ash.Policy.Authorizer]

  alias AshTemplate.Accounts.Refused
  alias AshTemplate.Actors.Human
  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.PageCursor
  alias AshTemplate.Points.Entries
  alias RegentPoints.Rules

  @points_off "Earning Points is off on this site."
  @spending_closed "Agent spending isn't open yet. Your person can do this themselves."
  @spending_ask "Your person can allow you to spend Credits on this site on their Regents account at regents.sh/account."

  actions do
    # Their Credits, and what the agent may spend of them: its grant, and whether a
    # grant can be made (`RegentCredits.agent_budget/1`). An agent that owns its
    # account spends as its owner, under no grant.
    action :account_balances, :map do
      run fn
        _input, %{actor: %Human{} = owner} ->
          {:ok, %{credits: RegentCredits.balance(owner.privy_user_id), spending_grant: nil}}

        _input, %{actor: actor} ->
          with :ok <- NotPaired.check(actor) do
            credit_actor = credit_actor(actor)

            case RegentCredits.agent_budget(actor: credit_actor) do
              {:ok, budget} ->
                answer = %{
                  credits: RegentCredits.balance(credit_actor.privy_user_id),
                  spending_grant: budget
                }

                {:ok, with_note(answer, spending_note(budget))}

              {:error, %Ash.Error.Forbidden{}} ->
                {:error, NotPaired.exception(code: "agent_not_paired")}

              error ->
                error
            end
          end
      end
    end

    # What came into and went out of their Credits, newest first, a page at a time.
    action :account_credits_history, :map do
      argument :after, :string,
        constraints: [max_length: 2048],
        description: "The previous page's next_cursor, unchanged, for older entries."

      run fn input, %{actor: actor} ->
        args = if cursor = input.arguments[:after], do: %{after: cursor}, else: %{}

        with :ok <- NotPaired.check(actor) do
          case RegentCredits.history(args, actor: credit_actor(actor)) do
            {:ok, history} ->
              {:ok,
               %{
                 entries: history.entries,
                 pagination: %{has_more: history.more?, next_cursor: history.next}
               }}

            {:error, error} ->
              if PageCursor.invalid?(error),
                do: {:error, Refused.exception(code: "invalid_cursor")},
                else: {:error, error}
          end
        end
      end
    end

    # Points as decimal text, the same figures the Points page shows.
    action :account_points, :map do
      run fn _input, %{actor: actor} ->
        with :ok <- NotPaired.check(actor),
             {:ok, summary} <- RegentPoints.summary(actor: actor),
             do: {:ok, with_note(Entries.answer(summary), points_note(Rules.active()))}
      end
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  @doc """
  The Credits library's actor on this site: an agent that owns its account
  acts as the person, and a paired agent as itself, under its grant.
  """
  def credit_actor(%Human{} = owner),
    do:
      RegentCredits.Actor.person(owner.privy_user_id, owner.wallet_addresses, AshTemplate.site())

  def credit_actor(actor) do
    RegentCredits.Actor.agent(
      actor.privy_user_id,
      actor.wallet_address,
      AshTemplate.site(),
      actor.pairing_id
    )
  end

  defp spending_note(%{site_allowed: true}), do: nil
  defp spending_note(%{grant_approvals_available: false}), do: @spending_closed
  defp spending_note(%{grant_approvals_available: true}), do: @spending_ask

  defp points_note([]), do: @points_off
  defp points_note(_earning), do: nil

  defp with_note(answer, nil), do: answer
  defp with_note(answer, note), do: Map.put(answer, :note, note)
end
