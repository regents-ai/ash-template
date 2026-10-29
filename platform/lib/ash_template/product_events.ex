defmodule AshTemplate.ProductEvents do
  @moduledoc """
  What people and agents reach on this site, one row each in `product_events`
  (`AshTemplate.ProductEvents.Event`), kept for good. Every site keeps the same
  names, each written only once the change it follows has committed, from the
  place the site already sees that change:

    * `account_created`: an account's first sign-in on this site, once per
      account, with where its browser first came from (`source`, and the link's
      `campaign`), from the browser's first-touch cookie
      (`AshTemplateWeb.VisitLog`).
    * `signed_in`: a sign-in that bound a browser to an account.
    * `visited`: a signed-in account's visit began (its `arrival`).
    * `agent_paired`: an agent paired with an account using its person's code;
      `kind` is the agent's harness.
    * `agent_acted`: a signed agent request that wrote something as the agent
      and succeeded; `kind` is its method and route.
    * `value_reached`: one of the site's own value actions, named with its `kind`
      in `config :ash_template, AshTemplate.ProductEvents, value_actions:` and
      written by `AshTemplate.ProductEvents.Notifier`.
    * `credits_bought`: Credits credited to an account; `kind` is `usdc` or
      `card`.

  The HTTP ones are read from the request's answer
  (`AshTemplateWeb.VisitLog.ProductEvents`). A row that cannot be written is
  logged and dropped: it never fails what the person or agent did. Nothing is
  written for a request or page from a browser that sends Global Privacy
  Control, as with the visit lines' `arrival` and `step`.

  `AshTemplate.ProductEvents.Cohorts` reads them back as weekly cohorts.
  """

  use Ash.Domain

  require Logger

  alias AshTemplate.AccessContext
  alias AshTemplate.Accounts
  alias AshTemplate.Accounts.HumanAccount
  alias AshTemplate.Actors.{Agent, Human, System}
  alias AshTemplate.ProductEvents.Event
  alias AshTemplateWeb.VisitLog

  @actor %System{}
  @surfaces %{
    "page" => :page,
    "webmcp" => :webmcp,
    "cli" => :cli,
    "agent_http" => :agent_http,
    "job" => :job
  }

  resources do
    resource Event
  end

  @doc """
  A sign-in that bound a browser to `account`: `account_created` with the
  browser's first touch the first time, then `signed_in`.
  """
  def signed_in(account, first_touch) do
    record(:account_created, account, first_touch)
    record(:signed_in, account)
  end

  @doc "A Credits purchase credited to the account `privy_user_id` names."
  def credited(%{privy_user_id: nil}, _kind), do: :ok

  def credited(%{purchase_id: purchase_id, privy_user_id: privy_user_id}, kind) do
    case Accounts.get_by_privy_did(privy_user_id, actor: @actor) do
      {:ok, %HumanAccount{} = account} ->
        record(:credits_bought, account, %{id: purchase_id, kind: kind})

      {:ok, nil} ->
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Writes the event `name` for `who` (an account, a person, an agent or a page's
  access context) with `fields`, unless this request or page came from a browser
  that sent Global Privacy Control, or `who` is nobody. Always `:ok`.
  """
  def record(name, who, fields \\ %{}) do
    case {VisitLog.gpc?(), ids(who)} do
      {false, %{} = ids} -> write(name, ids |> Map.merge(fields) |> Map.put(:surface, surface()))
      _untracked_or_nobody -> :ok
    end
  end

  defp surface, do: @surfaces[Logger.metadata()[:surface]]

  defp ids(%HumanAccount{id: id}), do: %{human_account_id: id}

  defp ids(%AccessContext{principal: {:human, %HumanAccount{id: id}}}),
    do: %{human_account_id: id}

  defp ids(%Human{human_account_id: id}), do: %{human_account_id: id}

  defp ids(%Agent{agent_id: agent, human_account_id: id}),
    do: %{human_account_id: id, agent_id: agent}

  defp ids(_nobody), do: nil

  # The write itself may raise or exit, as when the database cannot be reached.
  # Only the kinds of failure reach the line, never what the event holds.
  defp write(name, input) do
    case create(name, input) do
      {:ok, _event} -> :ok
      {:error, error} -> unwritten(kinds(error))
    end
  rescue
    error -> unwritten([error.__struct__])
  catch
    :exit, _reason -> unwritten([:exit])
  end

  defp create(:account_created, input),
    do: Ash.create(Event, input, action: :account_created, actor: @actor)

  defp create(:credits_bought, input),
    do: Ash.create(Event, input, action: :credits_bought, actor: @actor)

  defp create(name, input),
    do: Ash.create(Event, Map.put(input, :name, name), action: :record, actor: @actor)

  defp unwritten(kinds), do: Logger.warning("A product event wasn't written: #{inspect(kinds)}")

  defp kinds(%{errors: [_ | _] = errors}), do: Enum.map(errors, & &1.__struct__)
  defp kinds(%{__struct__: kind}), do: [kind]
  defp kinds(_other), do: [:unknown]
end
