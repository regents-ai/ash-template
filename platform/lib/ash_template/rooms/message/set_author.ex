defmodule AshTemplate.Rooms.Message.SetAuthor do
  @moduledoc """
  Makes the poster the message's author: a signed-in person or a signed-in agent.
  An agent the person paired posts as them, and the message names it; its pairing
  is checked again inside the post's transaction. An agent no person has paired
  here posts as itself, once: the post and the mark on the agent are one
  transaction, so a refused post leaves the mark unused. Such a post also counts
  against the hourly `:guest_post_address` allowance of the address it came from,
  which the caller passes as `context: %{client_key: key}`, so one network cannot
  post through many new wallets.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias AshTemplate.Actors.{Agent, Human, System}
  alias AshTemplate.Agents
  alias AshTemplate.Agents.Agent, as: AgentRecord
  alias AshTemplate.Limits
  alias AshTemplate.Rooms.Message.{GuestPostsLimited, PostedBeforePairing}

  @impl true
  def change(changeset, _opts, %{actor: %Human{} = human}) do
    Ash.Changeset.force_change_attributes(changeset,
      human_account_id: human.human_account_id,
      author_name: human.name,
      via_agent_id: human.acting_agent_id
    )
  end

  def change(changeset, _opts, %{actor: %Agent{pairing: :active} = agent} = context) do
    changeset
    |> Ash.Changeset.force_change_attributes(
      human_account_id: agent.human_account_id,
      via_agent_id: agent.agent_id,
      author_name: agent.name
    )
    |> RegentAgents.RequirePairing.change([repo: AshTemplate.Repo], context)
  end

  def change(changeset, _opts, %{actor: %Agent{} = agent}) do
    changeset
    |> Ash.Changeset.force_change_attributes(agent_id: agent.agent_id, author_name: agent.name)
    |> Ash.Changeset.before_action(&use_post_before_pairing(&1, agent))
  end

  # Anyone else is refused by the action's policy.
  def change(changeset, _opts, _context), do: changeset

  # Marks only an agent whose post is unused; the match and the mark are one
  # statement, so of two posts at once only one finds it unused.
  defp use_post_before_pairing(changeset, agent) do
    result =
      AgentRecord
      |> Ash.Query.filter(id == ^agent.agent_id and is_nil(posted_before_pairing_at))
      |> Agents.use_post_before_pairing(
        actor: %System{},
        bulk_options: [return_records?: true, return_errors?: true]
      )

    case result do
      %Ash.BulkResult{status: :success, records: [_agent]} ->
        spend_guest_post(changeset)

      %Ash.BulkResult{status: :success, records: []} ->
        Ash.Changeset.add_error(changeset, PostedBeforePairing.exception([]))

      %Ash.BulkResult{errors: errors} ->
        Ash.Changeset.add_error(changeset, errors)
    end
  end

  # Counted only once the agent's one post is free; a refusal here undoes the mark.
  defp spend_guest_post(%{context: %{client_key: key}} = changeset) do
    case Limits.spend_until(:guest_post_address, key) do
      :ok ->
        changeset

      {:limited, seconds} ->
        Ash.Changeset.add_error(changeset, GuestPostsLimited.exception(retry_after: seconds))
    end
  end
end
