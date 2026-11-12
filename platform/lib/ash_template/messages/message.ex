defmodule AshTemplate.Messages.Message do
  @moduledoc """
  One message left for the site's team under a `topic` the site names, such as
  `agents`: its text, where the sender wants an answer (`reply_to`) and who left
  it. A signed-in person or a signed agent leaves one, a few an hour at most,
  from each of them and from each network (`:message` and `:message_address` in
  `AshTemplate.Limits`). The sender is the actor, never an input (`SetSender`).
  Only the site's admins read messages (`RegentAgents.Checks.Admin`); the
  sender gets a receipt, `receipt/1`, and never reads them back.
  """

  use Ash.Resource,
    domain: AshTemplate.Messages,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias AshTemplate.Limits.LimitWrites
  alias AshTemplate.Messages.Message.{AgentLeave, SetSender}

  @topic [max_length: 40, match: ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/]
  @shown_text "Use letters, numbers and marks you can see."

  postgres do
    table "left_messages"
    repo(AshTemplate.Repo)

    custom_indexes do
      index([:inserted_at, :id])
    end

    check_constraints do
      check_constraint(:human_account_id, "has_sender",
        check: "human_account_id IS NOT NULL OR agent_id IS NOT NULL",
        message: "has a sender"
      )
    end
  end

  attributes do
    uuid_primary_key :id
    # A short name the site gives the place it was left from, such as agents.
    attribute :topic, :string, allow_nil?: false, public?: true, constraints: @topic
    attribute :body, :string, allow_nil?: false, public?: true, constraints: [max_length: 2000]
    # Where the sender wants an answer, in their own words.
    attribute :reply_to, :string, public?: true, constraints: [max_length: 200]
    # Who left it, as others saw them when they left it (`sender/1`): the name
    # they chose, else nil and their wallet shows, under its ENS name when it has
    # one. An agent is its profile name and its own wallet.
    attribute :sender_name, :string, public?: true
    attribute :sender_wallet, :string, public?: true
    attribute :sender_ens_name, :string, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    # The person it was left by or for: a signed-in person, or a paired agent's.
    belongs_to :human_account, AshTemplate.Accounts.HumanAccount do
      attribute_type :integer
      public? true
    end

    # The agent that left it, paired or not.
    belongs_to :agent, AshTemplate.Agents.Agent, public?: true
  end

  actions do
    defaults [:read]

    # The team's inbox, newest first, a page at a time.
    read :newest do
      prepare build(sort: [inserted_at: :desc, id: :desc], load: [:agent])
      pagination keyset?: true, default_limit: 50
    end

    create :leave do
      accept [:topic, :body, :reply_to]
      change SetSender
      validate match(:body, RegentFormat.Text.pattern()), message: @shown_text
      validate match(:reply_to, RegentFormat.Name.pattern()), message: @shown_text

      change {LimitWrites, allowance: :message, address_allowance: :message_address, field: :body}
    end

    # An agent's message, its operation_id spent once, as every surface answers it
    # (`AgentLeave`).
    action :agent_leave, :map do
      argument :topic, :string,
        allow_nil?: false,
        constraints: @topic,
        description:
          "The topic the site gives, such as agents: lowercase letters, numbers and hyphens, up to 40."

      argument :body, :string,
        allow_nil?: false,
        constraints: [max_length: 2000],
        description: "The message, 1 to 2,000 characters."

      argument :reply_to, :string,
        constraints: [max_length: 200],
        description:
          "Where you want an answer, up to 200 characters, such as an email address, a room or a profile. Leave it out for none."

      argument :operation_id, :uuid,
        allow_nil?: false,
        description:
          "A UUID you make for this message. Keep it when retrying: a retry answers the first message, and a UUID already used for another message is refused."

      run AgentLeave
    end
  end

  policies do
    policy action(:leave) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action(:agent_leave) do
      authorize_if actor_attribute_equals(:role, :agent)
    end

    # The site's admins on their team page; the site itself when it answers a
    # retried message with its receipt (`AgentLeave`).
    policy action_type(:read) do
      authorize_if RegentAgents.Checks.Admin
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  @doc "What the sender is told once a message is left: its id, topic and time."
  def receipt(message),
    do: %{id: message.id, topic: message.topic, inserted_at: message.inserted_at}

  @doc """
  Who left `message`, as `%{name, wallet, ens_name}`
  (`AshTemplate.PublicIdentity.person/1`).
  """
  def sender(message),
    do: %{
      name: message.sender_name,
      wallet: message.sender_wallet,
      ens_name: message.sender_ens_name
    }
end
