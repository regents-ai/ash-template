defmodule AshTemplate.Rooms.Removal do
  @moduledoc """
  One room message the site's operator removed, and why. It is written in the
  same transaction as the removal (`AshTemplate.Rooms.Message`, `:remove`) and
  never changed or deleted afterwards. It holds ids and the reason, never the
  message's words. Only the operator reads it.
  """

  use Ash.Resource,
    domain: AshTemplate.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "room_message_removals"
    repo(AshTemplate.Repo)
  end

  attributes do
    uuid_primary_key :id
    attribute :message_id, :uuid, allow_nil?: false
    attribute :room, :string, allow_nil?: false

    # Whose message it was: a person's account, or an agent posting as itself.
    attribute :human_account_id, :integer
    attribute :agent_id, :uuid

    attribute :reason, :string, allow_nil?: false, constraints: [max_length: 500]
    create_timestamp :inserted_at
  end

  actions do
    defaults [:read]

    create :record do
      accept [:message_id, :room, :human_account_id, :agent_id, :reason]
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end
end
