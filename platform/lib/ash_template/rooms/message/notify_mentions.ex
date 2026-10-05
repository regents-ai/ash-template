defmodule AshTemplate.Rooms.Message.NotifyMentions do
  @moduledoc """
  Tells each person a new message mentions. A mention is `@` followed by the
  name a person has posted under in that room, in any case. Nobody is told about
  their own message, or about one from someone they muted. The notifications
  are written in the post's own transaction, so a post that fails tells nobody,
  and they are published once it commits.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias AshTemplate.Activity.Notification
  alias AshTemplate.Actors.System
  alias AshTemplate.Rooms.{Message, Mute, Room}

  @excerpt 140

  @impl true
  def change(changeset, _opts, _context), do: Ash.Changeset.after_action(changeset, &notify/2)

  defp notify(_changeset, message) do
    case message |> mentioned() |> Enum.map(&notification(message, &1)) do
      [] ->
        {:ok, message}

      notifications ->
        result =
          Ash.bulk_create(notifications, Notification, :notify,
            actor: %System{},
            notify?: true,
            return_notifications?: true,
            return_errors?: true,
            stop_on_error?: true
          )

        case result do
          %Ash.BulkResult{status: :success, notifications: sent} -> {:ok, message, sent}
          %Ash.BulkResult{errors: errors} -> {:error, errors}
        end
    end
  end

  # Everyone else who has posted in the room under a name the message mentions,
  # less anyone who muted its author. These reads are the post's own
  # bookkeeping, so no reader's policies apply.
  defp mentioned(message) do
    named =
      Message
      |> Ash.Query.filter(
        room == ^message.room and not is_nil(human_account_id) and
          fragment("strpos(lower(?), '@' || lower(?)) > 0", ^message.body, author_name)
      )
      |> Ash.Query.select([:human_account_id])
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.human_account_id)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == message.human_account_id))

    muting = if named == [], do: [], else: muting(message, named)
    named -- muting
  end

  defp muting(%{human_account_id: nil, agent_id: agent_id}, named) do
    Mute
    |> Ash.Query.filter(muted_agent_id == ^agent_id and muter_account_id in ^named)
    |> muters()
  end

  defp muting(%{human_account_id: author_id}, named) do
    Mute
    |> Ash.Query.filter(muted_account_id == ^author_id and muter_account_id in ^named)
    |> muters()
  end

  defp muters(query) do
    query
    |> Ash.Query.select([:muter_account_id])
    # Who muted the author is the post's own bookkeeping, as above.
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.muter_account_id)
  end

  defp notification(message, human_account_id) do
    {:ok, room} = message.room |> Atom.to_string() |> Room.fetch()

    %{
      human_account_id: human_account_id,
      title: "#{message.author_name} mentioned you in #{room.name}",
      body: excerpt(message.body),
      path: "/rooms/#{room.slug}"
    }
  end

  defp excerpt(body) do
    line = body |> String.split("\n", parts: 2) |> hd()
    if String.length(line) > @excerpt, do: String.slice(line, 0, @excerpt - 1) <> "…", else: line
  end
end
