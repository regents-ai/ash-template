defmodule AshTemplate.Activity.Notification do
  @moduledoc """
  One thing a signed-in person should know about, such as someone mentioning
  them in a room. It is written in the same transaction as the thing it reports
  (`AshTemplate.Rooms.Message.NotifyMentions`), only its person can read it or
  mark it read, and each change is published on their own topic, so the bell on
  every page they have open counts it at once.
  """

  use Ash.Resource,
    domain: AshTemplate.Activity,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "notifications"
    repo(AshTemplate.Repo)

    custom_indexes do
      index([:human_account_id, :inserted_at])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true, constraints: [max_length: 200]
    attribute :body, :string, public?: true, constraints: [max_length: 200]
    # Where the notification leads on this site, such as "/rooms/general".
    attribute :path, :string, allow_nil?: false, public?: true
    attribute :read_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :human_account, AshTemplate.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  actions do
    defaults [:read]

    read :mine do
      prepare build(sort: [inserted_at: :desc, id: :desc], limit: 50)
    end

    read :unread do
      filter expr(is_nil(read_at))
    end

    create :notify do
      accept [:human_account_id, :title, :body, :path]
    end

    update :mark_read do
      change atomic_update(:read_at, expr(now()))
    end
  end

  policies do
    policy action(:notify) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    policy action_type([:read, :update]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  # Delivered after the transaction commits, as %{event: "notify" | "mark_read",
  # payload: notification}, to `topic/1` of the notification's person.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "notifications"
    broadcast_type :broadcast
    transform & &1.data

    publish :notify, [:human_account_id]
    publish :mark_read, [:human_account_id]
  end

  @doc "The topic every notification for `human_account_id`, and every read of one, is published on."
  def topic(human_account_id), do: "notifications:#{human_account_id}"
end
