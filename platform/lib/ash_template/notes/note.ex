defmodule AshTemplate.Notes.Note do
  @moduledoc """
  A note one signed-in person wrote. Only its writer can read, change or delete
  it, and every change is published on the writer's own topic, so each of their
  open pages shows it at once.
  """

  use Ash.Resource,
    domain: AshTemplate.Notes,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "notes"
    repo(AshTemplate.Repo)

    custom_indexes do
      index([:human_account_id, :inserted_at])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true, constraints: [max_length: 120]
    attribute :body, :string, public?: true, constraints: [max_length: 10_000]
    timestamps(public?: true)
  end

  relationships do
    belongs_to :human_account, AshTemplate.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  actions do
    defaults [:read, :destroy]

    read :mine do
      prepare build(sort: [inserted_at: :desc])
    end

    create :create do
      primary? true
      accept [:title, :body]
      change set_attribute(:human_account_id, actor(:human_account_id))
    end

    update :update do
      primary? true
      accept [:title, :body]
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if actor_attribute_equals(:role, :human)
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  # Delivered after the transaction commits, as %{event: "create" | "update" |
  # "destroy", payload: note}, to `topic/1` of the note's writer.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "notes"
    broadcast_type :broadcast
    transform & &1.data

    publish_all :create, [:human_account_id]
    publish_all :update, [:human_account_id]
    publish_all :destroy, [:human_account_id]
  end

  @doc "The topic every change to `human_account_id`'s notes is published on."
  def topic(human_account_id), do: "notes:#{human_account_id}"
end
