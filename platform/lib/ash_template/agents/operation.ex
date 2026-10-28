defmodule AshTemplate.Agents.Operation do
  @moduledoc """
  An operation key an agent spent: one row for each agent (`principal`, its
  record's id), capability and `operation_key`, written in the same transaction
  as the effect it names (`result_id`). The unique identity is what makes a
  retry, or two calls at once, with the same key produce one effect: the second
  insert waits for the first to commit and then fails, and the caller reads the
  committed row instead.

  `fingerprint` is the hash of what the key was spent on (for a room post, the
  room and the text). A reuse with the same fingerprint answers the existing
  result; any other is a conflict. Rows are kept for good, so a key whose result
  was later deleted stays spent.
  """

  use Ash.Resource,
    domain: AshTemplate.Agents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "agent_operations"
    repo(AshTemplate.Repo)
  end

  attributes do
    uuid_primary_key :id
    attribute :principal, :uuid, allow_nil?: false
    attribute :capability, :string, allow_nil?: false
    attribute :operation_key, :uuid, allow_nil?: false
    attribute :fingerprint, :string, allow_nil?: false
    attribute :result_id, :uuid, allow_nil?: false
    create_timestamp :inserted_at
  end

  identities do
    identity :spent_key, [:principal, :capability, :operation_key]
  end

  actions do
    defaults [:read]

    create :record do
      accept [:principal, :capability, :operation_key, :fingerprint, :result_id]
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  @doc "The hash an operation key is spent on: `parts`, in order, as one JSON list."
  @spec fingerprint([String.t()]) :: String.t()
  def fingerprint(parts),
    do: :sha256 |> :crypto.hash(Jason.encode!(parts)) |> Base.encode16(case: :lower)
end
