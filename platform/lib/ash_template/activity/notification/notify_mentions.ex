defmodule AshTemplate.Activity.Notification.NotifyMentions do
  @moduledoc """
  Tells each person a new message mentions, on the rooms' `:message_posted`
  signal. A mention is `@` followed by the name a person has posted under in
  that room, in any case. Nobody is told about their own message, or about one
  from someone they muted. The notifications are written in the post's own
  transaction, so a post that fails tells nobody, and they are published once
  it commits.
  """

  require Ash.Query

  alias AshTemplate.Activity.Notification
  alias AshTemplate.Actors.System
  alias AshTemplate.Rooms.{Message, Mute}

  @excerpt 140

  @doc "Writes the notifications for the message `signal` names; `:ok` or `{:error, errors}`."
  def notify(%{message_id: id}) do
    # The post's own bookkeeping: the message was just written in this transaction.
    message = Ash.get!(Message, id, authorize?: false, load: [:in_room])

    case message |> mentioned() |> Enum.map(&notification(message, &1)) do
      [] ->
        :ok

      notifications ->
        # Ash holds the notices until the post's transaction commits.
        result =
          Ash.bulk_create(notifications, Notification, :notify,
            actor: %System{},
            notify?: true,
            return_errors?: true,
            stop_on_error?: true
          )

        case result do
          %Ash.BulkResult{status: :success} -> :ok
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
    %{
      human_account_id: human_account_id,
      title: "#{message.author_name} mentioned you in #{message.in_room.name}",
      body: excerpt(message.body),
      path: "/rooms/#{message.room}"
    }
  end

  defp excerpt(body) do
    line = body |> String.split("\n", parts: 2) |> hd()
    if String.length(line) > @excerpt, do: String.slice(line, 0, @excerpt - 1) <> "…", else: line
  end
end
