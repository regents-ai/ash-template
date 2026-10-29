defmodule AshTemplate.Activity.Notification do
  @moduledoc """
  One thing a signed-in person should know about, such as someone mentioning
  them in a room. It is written in the same transaction as the thing it reports,
  on that thing's signal (`NotifyMentions` on the rooms' `:message_posted`),
  only its person can read it or
  mark it read, and each change is published on their own topic, so the bell on
  every page they have open counts it at once.
  """

  use Ash.Resource,
    domain: AshTemplate.Activity,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Activity.Notification.NotifyMentions
  alias AshTemplate.Activity.Refused
  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.PageCursor

  # The most one page may encode to; a page is never cut short to fit.
  @max_page_bytes 262_144

  postgres do
    table "notifications"
    repo(AshTemplate.Repo)

    custom_indexes do
      index([:human_account_id, :inserted_at])
      # The bell counts a person's unread notifications on every page, so this
      # index holds only those.
      index([:human_account_id],
        name: "notifications_unread_index",
        where: "read_at IS NULL",
        concurrently: true
      )
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

  signals_in do
    from AshTemplate.Rooms.Signals do
      on :message_posted, :notify_mentions
    end
  end

  actions do
    defaults [:read]

    action :notify_mentions do
      argument :signal, AshTemplate.Rooms.Signals.MessagePosted, allow_nil?: false
      run fn input, _context -> NotifyMentions.notify(input.arguments.signal) end
    end

    # Newest first, a page at a time.
    read :mine do
      prepare build(sort: [inserted_at: :desc, id: :desc])
      pagination keyset?: true, default_limit: 50, max_page_size: 50
    end

    read :unread do
      filter expr(is_nil(read_at))
    end

    # One page of the person's notifications, newest first, as every surface
    # gives it. Reading never marks a notification read.
    action :activity_list, :map do
      argument :after, :string,
        constraints: [max_length: 2048],
        description: "The previous page's next_cursor, unchanged, for older notifications."

      run fn input, %{actor: actor} ->
        page = if cursor = input.arguments[:after], do: [after: cursor], else: []

        with :ok <- NotPaired.check(actor) do
          case AshTemplate.Activity.list_my_notifications(
                 actor: actor,
                 page: Keyword.put(page, :limit, 50)
               ) do
            {:ok, page} -> activity_page(page)
            {:error, error} -> {:error, cursor_refusal(error)}
          end
        end
      end
    end

    create :notify do
      accept [:human_account_id, :title, :body, :path]
    end

    update :mark_read do
      change atomic_update(:read_at, expr(now()))
    end

    # Every unread notification of the agent's person marked read, as Mark all
    # read on /app/activity does. It takes no input.
    action :activity_mark_read, :map do
      run fn _input, %{actor: actor} ->
        with :ok <- NotPaired.check(actor) do
          case AshTemplate.Activity.mark_all_read(actor: actor) do
            %Ash.BulkResult{status: :success} ->
              {:ok, %{marked_read: true}}

            %Ash.BulkResult{errors: errors} ->
              NotPaired.ended({:error, Ash.Error.to_error_class(errors)}, actor)
          end
        end
      end
    end
  end

  policies do
    # Reached only through the rooms' signal, after the post itself was allowed;
    # it writes each notification as the system.
    policy action(:notify_mentions) do
      authorize_if always()
    end

    policy action(:notify) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    policy action([:activity_list, :activity_mark_read]) do
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action_type([:read, :update]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end

    # An agent marks its person's notifications read only while it is paired,
    # checked again when the change is made, as every agent write is.
    policy action(:mark_read) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
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

  defp activity_page(page) do
    answer = %{
      notifications:
        Enum.map(page.results, fn notification ->
          %{
            id: notification.id,
            title: notification.title,
            body: notification.body,
            path: notification.path,
            read_at: notification.read_at && DateTime.to_iso8601(notification.read_at),
            inserted_at: DateTime.to_iso8601(notification.inserted_at)
          }
        end),
      pagination: %{has_more: page.more?, next_cursor: next_cursor(page)}
    }

    if IO.iodata_length(Jason.encode_to_iodata!(answer)) <= @max_page_bytes,
      do: {:ok, answer},
      else: {:error, Refused.exception(code: "activity_too_large")}
  end

  defp next_cursor(%{more?: true, results: results}),
    do: List.last(results).__metadata__.keyset

  defp next_cursor(_page), do: nil

  defp cursor_refusal(error) do
    if PageCursor.invalid?(error), do: Refused.exception(code: "invalid_cursor"), else: error
  end
end
