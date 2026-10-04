defmodule AshTemplate.Rooms.Message.LimitPosts do
  @moduledoc """
  Holds each person, and each agent, to a few posts a minute
  (`config :ash_template, :room_post_rate_limit`). A post counts when it is
  saved, not while it is typed, so checking a draft never uses the allowance.
  """

  use Ash.Resource.Change

  alias AshTemplate.Accounts.RequestRateLimiter
  alias AshTemplate.Actors.{Agent, Human}

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      config = Application.fetch_env!(:ash_template, :room_post_rate_limit)
      key = {:room_post, poster(actor)}

      case RequestRateLimiter.admit(key, config[:limit], config[:window_seconds]) do
        {:ok, _budget} ->
          changeset

        {:error, :rate_limited, _budget} ->
          Ash.Changeset.add_error(changeset,
            field: :body,
            message: "You're posting quickly. Wait a moment and try again."
          )
      end
    end)
  end

  defp poster(%Human{human_account_id: id}), do: {:human, id}
  defp poster(%Agent{agent_id: id}), do: {:agent, id}
end
