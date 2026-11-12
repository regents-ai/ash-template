defmodule AshTemplateWeb.Presence do
  @moduledoc """
  Who has a room open. Each signed-in person's open room pages are tracked on
  `topic/1` under their account id, so several tabs count once; visitors who
  are not signed in are not listed.
  """

  use Phoenix.Presence, otp_app: :ash_template, pubsub_server: AshTemplate.PubSub

  @doc "The topic a room's arrivals and departures are published on."
  def topic(room), do: "room_people:#{room}"

  @doc "Shows `human` as here in `room` while the calling process lives."
  def join(room, human),
    do: track(self(), topic(room), Integer.to_string(human.human_account_id), human.person)

  @doc "Stops showing the calling process in `room`."
  def leave(room, human),
    do: untrack(self(), topic(room), Integer.to_string(human.human_account_id))

  @doc """
  Everyone in `room`, as `%{id: account_id, name, wallet, ens_name}`
  (`AshTemplate.PublicIdentity.person/1`), ordered by name.
  """
  def people(room) do
    topic(room)
    |> list()
    |> Enum.map(fn {id, %{metas: [meta | _]}} ->
      meta |> Map.take([:name, :wallet, :ens_name]) |> Map.put(:id, String.to_integer(id))
    end)
    |> Enum.sort_by(&String.downcase(AshTemplate.PublicIdentity.words(&1)))
  end
end
