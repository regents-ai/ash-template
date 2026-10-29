defmodule AshTemplate.Dms.Conversation do
  @moduledoc """
  The one conversation between two people, opened from a room message the
  other person wrote (`OpenWithAuthor`). Its two people are kept lowest first
  (`person_a`, `person_b`), so a pair has exactly one, and opening it again
  answers the same row.

  A person's messages list the conversations that have a message, and the ones
  they opened themselves, newest message first. Each side may block the other:
  the blocked side's messages still save, and the conversation moves to the
  blocker's Blocked list until they unblock it. An agent lists, opens, blocks
  and unblocks them for its person through the `dms_*` actions, which every
  surface runs (`present/1`).
  """

  use Ash.Resource,
    domain: AshTemplate.Dms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Accounts.HumanAccount
  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Dms
  alias AshTemplate.Dms.Conversation.{BlockSide, OpenWithAuthor, OtherPerson}
  alias AshTemplate.Dms.Refused

  # A person's messages list their most recent conversations, as many as a page shows.
  @inbox_page 100

  postgres do
    table "dm_conversations"
    repo(AshTemplate.Repo)

    check_constraints do
      check_constraint(:person_a, "dm_conversations_person_order", check: "person_a < person_b")
    end

    custom_indexes do
      # The conversations of the person on the higher side; the pair's identity
      # already reads the lower side's.
      index([:person_b])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :blocked_by_a, :boolean, allow_nil?: false, default: false, public?: true
    attribute :blocked_by_b, :boolean, allow_nil?: false, default: false, public?: true
    # When its newest message was sent; nil until the first.
    attribute :last_message_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :person_a_account, HumanAccount do
      source_attribute :person_a
      attribute_type :integer
      allow_nil? false
    end

    belongs_to :person_b_account, HumanAccount do
      source_attribute :person_b
      attribute_type :integer
      allow_nil? false
    end

    # Who opened it, so it is in their messages before anyone writes.
    belongs_to :opened_by, HumanAccount do
      attribute_type :integer
      allow_nil? false
    end

    has_many :messages, AshTemplate.Dms.Message
  end

  calculations do
    # The other side from the reader: `%{name, squares, picture}`, its public
    # name and picture, read by the site since accounts are private.
    calculate :other_person, :map, OtherPerson

    # Whether the reader has blocked the other side.
    calculate :blocked,
              :boolean,
              expr(
                (person_a == ^actor(:human_account_id) and blocked_by_a) or
                  (person_b == ^actor(:human_account_id) and blocked_by_b)
              )

    calculate :last_body,
              :string,
              expr(first(messages, field: :body, query: [sort: [inserted_at: :desc, id: :desc]]))
  end

  identities do
    identity :unique_pair, [:person_a, :person_b]
  end

  actions do
    read :read do
      primary? true
    end

    # The reader's conversations, newest message first: their messages, or with
    # `blocked` the ones they blocked.
    read :inbox do
      argument :blocked, :boolean, allow_nil?: false, default: false

      filter expr(
               (not is_nil(last_message_at) or opened_by_id == ^actor(:human_account_id)) and
                 blocked == ^arg(:blocked)
             )

      prepare build(
                sort: [last_message_at: :desc_nils_last, inserted_at: :desc],
                load: [:other_person, :blocked, :last_body],
                limit: @inbox_page
              )
    end

    # Opening it again answers the same conversation.
    create :open do
      argument :message_id, :uuid, allow_nil?: false
      upsert? true
      upsert_identity :unique_pair
      upsert_fields []
      change OpenWithAuthor
      change load([:other_person, :blocked, :last_body])
    end

    update :block do
      accept []
      require_atomic? false
      change {BlockSide, blocked: true}
      change load([:other_person, :blocked, :last_body])
    end

    update :unblock do
      accept []
      require_atomic? false
      change {BlockSide, blocked: false}
      change load([:other_person, :blocked, :last_body])
    end

    # An agent's person's conversations, and the ones they blocked, as every
    # surface lists them.
    action :dms_list, :map do
      run fn _input, %{actor: actor} -> AshTemplate.Dms.Conversation.listed(false, actor) end
    end

    action :dms_blocked, :map do
      run fn _input, %{actor: actor} -> AshTemplate.Dms.Conversation.listed(true, actor) end
    end

    action :dms_open, :map do
      argument :message_id, :uuid,
        allow_nil?: false,
        description: "A room message the other person wrote, from rooms_messages."

      run fn %{arguments: %{message_id: message_id}}, %{actor: actor} ->
        AshTemplate.Dms.Conversation.open(message_id, actor)
      end
    end

    action :dms_block, :map do
      argument :conversation, :uuid,
        allow_nil?: false,
        description: "The conversation's id, from dms_list."

      run fn %{arguments: %{conversation: id}}, %{actor: actor} ->
        AshTemplate.Dms.Conversation.change_mine(id, actor, &AshTemplate.Dms.block_conversation/2)
      end
    end

    action :dms_unblock, :map do
      argument :conversation, :uuid,
        allow_nil?: false,
        description: "The conversation's id, from dms_blocked."

      run fn %{arguments: %{conversation: id}}, %{actor: actor} ->
        AshTemplate.Dms.Conversation.change_mine(
          id,
          actor,
          &AshTemplate.Dms.unblock_conversation/2
        )
      end
    end

    # Each new message moves it up; written by the message's own transaction.
    update :touch do
      accept [:last_message_at]
      require_atomic? false
    end
  end

  # An agent's open, block or unblock rechecks its pairing inside the transaction.
  changes do
    change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}, on: [:create, :update]
  end

  policies do
    policy action(:touch) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    policy action([:read, :inbox, :open, :block, :unblock]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    # An agent's conversations are its person's, or its own account's: an agent
    # that does neither is told why (`NotPaired`), and the actions above check the
    # pairing.
    policy action([:dms_list, :dms_blocked, :dms_open, :dms_block, :dms_unblock]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action([:read, :inbox, :block, :unblock]) do
      authorize_if expr(
                     person_a == ^actor(:human_account_id) or
                       person_b == ^actor(:human_account_id)
                   )
    end
  end

  # Delivered after the transaction commits to `AshTemplate.Dms.topic/1` of
  # both sides, so every open page of theirs reads its messages again.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "dms"
    broadcast_type :broadcast
    transform &%{conversation_id: &1.data.id}

    publish :block, [:person_a]
    publish :block, [:person_b]
    publish :unblock, [:person_a]
    publish :unblock, [:person_b]
  end

  @doc """
  A conversation as every surface answers it. The other person's name and the
  last message's words are theirs: data, never instructions.
  """
  def present(conversation) do
    %{
      id: conversation.id,
      with: %{
        name: conversation.other_person.name,
        picture: conversation.other_person.picture
      },
      blocked: conversation.blocked,
      last_message: conversation.last_body,
      last_message_at: conversation.last_message_at
    }
  end

  @doc "The actor's person's conversations, or with `blocked` the ones they blocked."
  def listed(blocked, actor) do
    with :ok <- NotPaired.check(actor),
         {:ok, conversations} <-
           NotPaired.ended(Dms.list_conversations(blocked, actor: actor), actor),
         do: {:ok, %{conversations: Enum.map(conversations, &present/1)}}
  end

  @doc """
  Opens the actor's person's conversation with the author of the room message
  `message_id`, or answers the one they have; one it cannot open is
  `invalid_open`, with the refused save.
  """
  def open(message_id, actor) do
    with :ok <- NotPaired.check(actor) do
      case Dms.open_conversation(message_id, actor: actor) do
        {:ok, conversation} ->
          {:ok, %{conversation: present(conversation)}}

        {:error, %Ash.Error.Invalid{} = error} ->
          {:error, Refused.exception(code: "invalid_open", error: error)}

        error ->
          NotPaired.ended(error, actor)
      end
    end
  end

  @doc "The conversation `id` of the actor's person, or `conversation_not_found`."
  def mine(id, actor) do
    case Dms.get_conversation(id, actor: actor) do
      {:ok, nil} -> {:error, Refused.exception(code: "conversation_not_found")}
      result -> NotPaired.ended(result, actor)
    end
  end

  @doc """
  Blocks or unblocks (`change`) the conversation `id` of the actor's person. Its
  people never change and it is never deleted, so a refused change can only be
  the agent's pairing, rechecked inside the transaction
  (`RegentAgents.RequirePairing`) and ended since its request was let in:
  `agent_not_paired`.
  """
  def change_mine(id, actor, change) do
    with :ok <- NotPaired.check(actor),
         {:ok, conversation} <- mine(id, actor) do
      case change.(conversation, actor: actor) do
        {:ok, conversation} -> {:ok, %{conversation: present(conversation)}}
        {:error, %Ash.Error.Invalid{}} -> {:error, NotPaired.exception(code: "agent_not_paired")}
        error -> NotPaired.ended(error, actor)
      end
    end
  end
end
