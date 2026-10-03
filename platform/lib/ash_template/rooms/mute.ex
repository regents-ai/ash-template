defmodule AshTemplate.Rooms.Mute do
  @moduledoc """
  One signed-in person muting another: the muted person's messages and their
  place in "Here now" stay out of every room the muter reads. Only the muter
  can see or lift a mute. A person is muted from one of their messages, so no
  page ever handles another account's id. Each change is published on the
  muter's own topic, so all their open pages update at once.
  """

  use Ash.Resource,
    domain: AshTemplate.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Accounts.HumanAccount
  alias AshTemplate.Rooms.Mute.MuteAuthor

  postgres do
    table "room_mutes"
    repo(AshTemplate.Repo)
  end

  attributes do
    uuid_primary_key :id

    # The muted person's name when they were last muted, for the muter's list.
    attribute :muted_name, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :muter_account, HumanAccount do
      allow_nil? false
      attribute_type :integer
    end

    belongs_to :muted_account, HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  identities do
    identity :one_per_pair, [:muter_account_id, :muted_account_id]
  end

  actions do
    defaults [:read, :destroy]

    read :mine do
      prepare build(sort: [inserted_at: :desc])
    end

    # Muting someone already muted keeps the one mute and refreshes their name.
    create :mute do
      argument :message_id, :uuid, allow_nil?: false
      upsert? true
      upsert_identity :one_per_pair
      upsert_fields [:muted_name]
      change set_attribute(:muter_account_id, actor(:human_account_id))
      change MuteAuthor
    end
  end

  policies do
    policy action(:mute) do
      authorize_if actor_attribute_equals(:role, :human)
    end

    policy action_type([:read, :destroy]) do
      authorize_if expr(muter_account_id == ^actor(:human_account_id))
    end
  end

  # Delivered after the transaction commits, as %{event: "mute" | "destroy",
  # payload: mute}, to `topic/1` of the muter.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "mutes"
    broadcast_type :broadcast
    transform & &1.data

    publish :mute, [:muter_account_id]
    publish :destroy, [:muter_account_id]
  end

  @doc "The topic every mute and unmute by `human_account_id` is published on."
  def topic(human_account_id), do: "mutes:#{human_account_id}"
end
