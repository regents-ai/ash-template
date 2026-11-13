defmodule AshTemplate.Rooms.Poster do
  @moduledoc """
  A name a person has posted under in a room: one row for each room, person and
  name, written by the post itself (`AshTemplate.Rooms.Message.RecordPoster`)
  and removed with the last of their messages there, deleted or removed
  (`AshTemplate.Rooms.Message.ForgetPoster`).
  A mention is `@` and one of these names (`AshTemplate.Activity.Notification.NotifyMentions`),
  so finding who a post mentions reads the room's posters, never its history. A
  person who changed their name keeps a row for each name, as each of their
  messages kept the name it was posted under.

  The name is what others saw them post under in plain words, exactly as a
  mention has always matched it: the name they chose, else their ENS name, else
  their wallet shortened to `0x1234..abcd`. An agent posting as itself names
  nobody a mention could reach, so it has none. These rows are the site's own
  bookkeeping, read and written as the system only.
  """

  use Ash.Resource,
    domain: AshTemplate.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "room_posters"
    repo(AshTemplate.Repo)
  end

  attributes do
    # The room's slug.
    attribute :room, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :human_account_id, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, primary_key?: true, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read]

    # A name already recorded writes nothing: the conflict updates no row.
    create :record do
      accept [:room, :human_account_id, :name]
      upsert? true
      upsert_fields []
      upsert_condition expr(false)
    end

    # A person whose last message in the room is gone (`ForgetPoster`).
    destroy :forget
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  @doc """
  The name `message`'s author posted under, as a mention matches it, or nil
  when the author is not a person or shows no name.
  """
  def name(%{human_account_id: nil}), do: nil
  def name(%{author_name: name}) when is_binary(name), do: name
  def name(%{author_ens_name: ens_name}) when is_binary(ens_name), do: ens_name

  def name(%{author_wallet: wallet}) when is_binary(wallet),
    do: "0x" <> String.slice(wallet, 2, 4) <> ".." <> String.slice(wallet, -4, 4)

  def name(_message), do: nil
end
