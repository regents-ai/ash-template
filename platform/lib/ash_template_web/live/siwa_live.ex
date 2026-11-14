defmodule AshTemplateWeb.SiwaLive do
  @moduledoc """
  The SIWA pages, where a person runs their company's agent sign-in: Overview
  (`/siwa`), Sites (`/siwa/sites`), one site with its keys
  (`/siwa/sites/:site_id`) and Settings (`/siwa/settings`). All of it is read
  from the sign-in service's control API (`AshTemplate.SiwaControl`) each time;
  this site keeps none of it. A person with no company names it first, then
  lands on Sites.

  Overview shows the company's billing period from the account read: its dates,
  the agents counted against those included, the fee so far and the cap, which
  the person sets, changes or removes there. With no period running it says
  billing hasn't started. Once one runs, a second read lists the period's agents,
  newest first, into a stream, a page at a time by the service's cursor, so the
  page keeps none of the rows.

  The service is asked with the control token this browser's sign-in traded for
  (`AshTemplateWeb.SiwaSessionController`), which only this machine holds
  (`AshTemplate.SiwaControl.Tokens`). When there is none, or the service says it
  has ended, the page asks the browser's sign-in to trade again (the
  `SiwaControl` hook) and runs what was waiting once it has. Each read and each
  change is tried again once after a trade; one that still finds no token says
  to sign in again. A trade refused for too many tries shows Busy, and one SIWA
  can't make shows Unavailable; neither is tried again until the person asks.

  A new site key goes from the service's answer straight to the browser, into
  its box on the page, and is never kept in the page's state, so no later
  render, log or crash report holds it.

  The shell passes `lease` (its `session_lease`), `account`, `signed_out_reason`,
  `page` (its live action) and `site_id`.
  """
  use AshTemplateWeb, :live_component

  import AshTemplateWeb.Components.PageHead, only: [page_head: 1]

  alias AshTemplate.Accounts.SessionAuthority
  alias AshTemplate.PublicIdentity
  alias AshTemplate.SiwaControl
  alias AshTemplate.SiwaControl.{Refusal, Secret, Tokens}
  alias AshTemplateWeb.Live.Session
  alias AshTemplateWeb.{Motion, Read}
  alias Regent.Primitives, as: P

  @reads [:company, :sites, :site, :agents, :more_agents]
  @forms ~w(company site details cap)
  @fields %{
    "company" => ~w(name),
    "site" => ~w(name audience environment origins),
    "details" => ~w(name origins)
  }

  # The service's bounds for a cap, in cents: the fee for the agents a period
  # includes, and the largest it keeps.
  @least_cap 9_900
  @most_cap 2_147_483_647
  @dollars ~r/\A[0-9]+(\.[0-9]{1,2})?\z/

  # An agent is a wallet on one of the chains SIWA signs agents in on.
  @subject ~r/\Aeip155:(1|8453):(0x[0-9a-f]{40})\z/
  @chains %{"1" => {"ethereum", "Ethereum"}, "8453" => {"base", "Base"}}
  @labels %{
    "name" => "Name",
    "audience" => "Audience",
    "environment" => "Environment",
    "origins" => "Origins"
  }

  # The site's own words for the refusals a person can meet here; any other is
  # shown in the service's words.
  @refusals %{
    "site_not_found" => "This site doesn't exist, or it was archived.",
    "site_key_not_found" => "This key doesn't exist. Reload the page to see the site's keys.",
    "site_key_limit" => "A site can have 5 keys in use. Revoke one, then make another.",
    "customer_not_found" => "Your company isn't set up yet. Reload the page to name it."
  }

  @unavailable "SIWA isn't available right now. Try again later."

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> Session.check_component_lease(&assign(&1, :account, &2))
     |> assign(owner: nil, company: %Read{}, sites: %Read{}, site: %Read{})
     |> assign(agents: %Read{}, more_agents: %Read{})
     |> stream_configure(:agents, dom_id: &"siwa-agent-#{&1.chain}-#{&1.address}")
     |> fresh()}
  end

  # A page for another account, another tab or another site starts afresh; the
  # company already read for the same account is kept.
  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    owner = owner(socket.assigns)

    if owner == socket.assigns.owner,
      do: {:ok, socket},
      else: {:ok, socket |> assign(owner: owner) |> fresh() |> begin()}
  end

  defp owner(%{account: nil}), do: nil
  defp owner(%{account: account, page: page, site_id: site_id}), do: {account.id, page, site_id}

  # The agents listed so far go too, and any page of them still on its way is
  # dropped when it lands.
  defp fresh(socket) do
    socket
    |> assign(
      control: :ready,
      waiting: [],
      again: MapSet.new(),
      busy: %{},
      adding: false,
      drafts: %{},
      errors: %{},
      notices: %{},
      revealed: nil,
      next: nil,
      names: %{}
    )
    |> Read.clear(:agents)
    |> Read.clear(:more_agents)
    |> stream(:agents, [], reset: true)
  end

  # Overview and Settings read the company each time; the other pages read it once.
  defp begin(%{assigns: %{owner: nil}} = socket), do: socket

  defp begin(socket) do
    if socket.assigns.page in [:siwa_sites, :siwa_site] and known_company?(socket.assigns),
      do: run_page(socket),
      else: run(socket, :company)
  end

  defp known_company?(%{
         company: %Read{owner: id, value: %{"customer" => %{"id" => _}}},
         account: %{id: id}
       }),
       do: true

  defp known_company?(_assigns), do: false

  defp run_page(%{assigns: %{page: :siwa_sites}} = socket), do: run(socket, :sites)
  defp run_page(%{assigns: %{page: :siwa_site}} = socket), do: run(socket, :site)

  # A period with no agents yet has none to list.
  defp run_page(
         %{
           assigns: %{
             page: :siwa_overview,
             company: %Read{value: %{"usage" => %{"activeAgents" => counted}}}
           }
         } = socket
       )
       when counted > 0,
       do: run(socket, :agents)

  defp run_page(socket), do: socket

  @impl true
  def handle_event("traded", %{"outcome" => outcome}, socket),
    do: {:noreply, traded(socket, outcome)}

  def handle_event("retry", _params, socket), do: {:noreply, socket |> fresh() |> begin()}

  def handle_event("draft", params, socket),
    do: {:noreply, update(socket, :drafts, &Map.merge(&1, Map.take(params, @forms)))}

  def handle_event("create_company", %{"company" => params}, socket),
    do: {:noreply, submit(socket, "company", params, {:create_company, name(params)})}

  def handle_event("update_company", %{"company" => params}, socket),
    do: {:noreply, submit(socket, "company", params, {:update_company, name(params)})}

  def handle_event("create_site", %{"site" => params}, socket) do
    site =
      params
      |> Map.take(~w(name audience environment))
      |> Map.put("origins", origins(params["origins"]))

    {:noreply, submit(socket, "site", params, {:create_site, site})}
  end

  # The service takes a site's name and origins together.
  def handle_event("update_site", %{"details" => params}, socket) do
    details = %{"name" => params["name"], "origins" => origins(params["origins"])}
    {:noreply, submit(socket, "details", params, {:update_site, socket.assigns.site_id, details})}
  end

  def handle_event("make_key", _params, socket),
    do: {:noreply, act(socket, {:make_key, socket.assigns.site_id})}

  def handle_event("revoke_key", %{"id" => key_id}, socket),
    do: {:noreply, act(socket, {:revoke_key, socket.assigns.site_id, key_id})}

  def handle_event("archive", _params, socket),
    do: {:noreply, act(socket, {:archive, socket.assigns.site_id})}

  def handle_event("add_site", _params, socket), do: {:noreply, assign(socket, adding: true)}

  def handle_event("cancel_site", _params, socket) do
    {:noreply,
     socket
     |> assign(adding: false)
     |> update(:drafts, &Map.delete(&1, "site"))
     |> update(:errors, &Map.delete(&1, "site"))
     |> update(:notices, &Map.delete(&1, "site"))}
  end

  def handle_event("hide_key", _params, socket), do: {:noreply, assign(socket, revealed: nil)}

  def handle_event("set_cap", %{"cap" => %{"amount" => amount} = params}, socket) do
    case cents(amount) do
      {:ok, cap_cents} ->
        {:noreply, submit(socket, "cap", params, {:set_cap, cap_cents})}

      {:error, words} ->
        {:noreply,
         socket
         |> update(:drafts, &Map.put(&1, "cap", params))
         |> update(:notices, &Map.delete(&1, "cap"))
         |> cap_error(words)}
    end
  end

  def handle_event("remove_cap", _params, socket) do
    {:noreply,
     socket
     |> update(:drafts, &Map.delete(&1, "cap"))
     |> update(:errors, &Map.delete(&1, "cap"))
     |> act({:set_cap, nil})}
  end

  def handle_event("list_agents", _params, socket), do: {:noreply, run(socket, :agents)}

  # A press after the last page landed has nothing more to read.
  def handle_event("more_agents", _params, %{assigns: %{next: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("more_agents", _params, socket), do: {:noreply, run(socket, :more_agents)}

  defp name(params), do: Map.take(params, ["name"])

  # Dollars as the person typed them, with or without its sign and commas, in
  # whole cents. The service says whether it is enough.
  defp cents(amount) do
    dollars = String.replace(amount, ~r/[\s$,]/u, "")

    if Regex.match?(@dollars, dollars),
      do: dollars |> Decimal.new() |> Decimal.mult(100) |> Decimal.to_integer() |> at_most(),
      else: {:error, "Enter the cap in dollars, such as 500 or 500.00."}
  end

  defp at_most(cents) when cents > @most_cap,
    do: {:error, "Set a cap of at most #{money(@most_cap)}."}

  defp at_most(cents), do: {:ok, cents}

  # One origin a line, as the person typed them.
  defp origins(text) do
    text
    |> to_string()
    |> String.split(["\r\n", "\n"])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp submit(socket, form, params, op) do
    socket
    |> update(:drafts, &Map.put(&1, form, params))
    |> update(:errors, &Map.delete(&1, form))
    |> act(op)
  end

  defp act(socket, op), do: socket |> update(:notices, &Map.delete(&1, section(op))) |> run(op)

  # Nothing is asked before the page has connected with its sign-in.
  defp run(%{assigns: %{lease: nil}} = socket, _op), do: socket

  defp run(socket, name) when name in @reads do
    ctx = ctx(socket.assigns)
    Read.start(socket, name, read_owner(name, ctx), fn -> read(name, ctx) end)
  end

  defp run(socket, op) do
    ctx = ctx(socket.assigns)
    ref = make_ref()

    socket
    |> update(:busy, &Map.put(&1, ref, op))
    |> start_async({:write, ref}, fn -> call(ctx, &write(op, &1)) end)
  end

  defp ctx(%{lease: lease, account: account, site_id: site_id, next: next, names: names}) do
    %{
      topic: SessionAuthority.topic(lease.lineage),
      account_id: account.id,
      site_id: site_id,
      next: next,
      names: names
    }
  end

  defp read_owner(:site, ctx), do: {ctx.account_id, ctx.site_id}
  defp read_owner(_name, ctx), do: ctx.account_id

  # A refusal is something to show, not a read that failed; only a service that
  # did not answer, or says it cannot, fails the read.
  defp read(:company, ctx) do
    ctx
    |> call(&SiwaControl.account/1)
    |> then(&with({:ok, data} <- &1, do: {:ok, Map.take(data, ["customer", "usage"])}))
    |> shown()
  end

  # The first page of agents comes with the company's sites, so each agent's
  # first site shows by its name; the later pages use the same names.
  defp read(:agents, ctx) do
    ctx
    |> call(fn token ->
      with {:ok, %{"sites" => sites}} <- SiwaControl.list_sites(token),
           {:ok, page} <- SiwaControl.list_agents(token, nil),
           do: agents(page, Map.new(sites, &{&1["id"], &1["name"]}))
    end)
    |> shown()
  end

  defp read(:more_agents, %{next: next, names: names} = ctx) do
    ctx
    |> call(&with({:ok, page} <- SiwaControl.list_agents(&1, next), do: agents(page, names)))
    |> shown()
  end

  defp read(:sites, ctx) do
    ctx
    |> call(&SiwaControl.list_sites/1)
    |> then(&with({:ok, %{"sites" => sites}} <- &1, do: {:ok, sites}))
    |> shown()
  end

  defp read(:site, %{site_id: id} = ctx) do
    ctx
    |> call(fn token ->
      with {:ok, site} <- SiwaControl.get_site(token, id),
           {:ok, %{"keys" => keys}} <- SiwaControl.list_site_keys(token, id),
           do: {:ok, %{site: site, keys: keys}}
    end)
    |> shown()
  end

  defp shown({:error, %Refusal{status: status} = refusal}) when status != 503,
    do: {:ok, {:refused, refusal}}

  defp shown(result), do: result

  # A page of agents as the list shows them. An agent that isn't a wallet on a
  # chain SIWA signs in on means the service answered something else.
  defp agents(%{"agents" => agents, "next" => next}, names) do
    rows = Enum.map(agents, &agent(&1, names))

    if Enum.all?(rows, &is_map/1),
      do: {:ok, %{rows: rows, next: next, names: names}},
      else: {:error, :unavailable}
  end

  defp agents(_other, _names), do: {:error, :unavailable}

  defp agent(%{"subject" => subject, "firstVerifiedAt" => at, "firstSiteId" => site_id}, names)
       when is_binary(subject) and is_binary(at) do
    with [chain_id, address] <- Regex.run(@subject, subject, capture: :all_but_first),
         {:ok, at, _offset} <- DateTime.from_iso8601(at) do
      {chain, chain_name} = Map.fetch!(@chains, chain_id)

      %{
        chain: chain,
        chain_name: chain_name,
        address: address,
        at: at,
        site: Map.get(names, site_id)
      }
    end
  end

  defp agent(_other, _names), do: nil

  defp write({:set_cap, cap_cents}, token), do: SiwaControl.set_cap(token, cap_cents)
  defp write({:create_company, params}, token), do: SiwaControl.create_customer(token, params)
  defp write({:update_company, params}, token), do: SiwaControl.update_customer(token, params)
  defp write({:create_site, params}, token), do: SiwaControl.create_site(token, params)
  defp write({:update_site, id, params}, token), do: SiwaControl.update_site(token, id, params)
  defp write({:make_key, id}, token), do: SiwaControl.create_site_key(token, id)
  defp write({:revoke_key, id, key_id}, token), do: SiwaControl.revoke_site_key(token, id, key_id)
  defp write({:archive, id}, token), do: SiwaControl.archive_site(token, id)

  # The token this browser's sign-in holds here, or word that a trade is needed:
  # there is none, or the service says it is no longer good (`control_token_invalid`
  # is its one answer for that, and covers every token a release of the service voids).
  defp call(%{topic: topic, account_id: account_id}, fun) do
    case Tokens.token(topic, account_id) do
      {:ok, token} -> token |> fun.() |> ended()
      :error -> {:error, :sign_in}
    end
  end

  defp ended({:error, %Refusal{status: 401, code: "control_token_invalid"}}),
    do: {:error, :sign_in}

  defp ended(result), do: result

  @impl true
  def handle_async({Read, name, generation} = key, result, socket) do
    cond do
      Map.fetch!(socket.assigns, name).generation != generation ->
        {:noreply, socket}

      result == {:ok, {:error, :sign_in}} ->
        {:noreply, needs_trade(socket, name)}

      true ->
        {:noreply, socket |> Read.settle(key, result) |> settled(name) |> landed(name)}
    end
  end

  # A change from before the page moved on is dropped here; the next read shows it.
  def handle_async({:write, ref}, result, socket) do
    case Map.pop(socket.assigns.busy, ref) do
      {nil, _busy} ->
        {:noreply, socket}

      {op, busy} ->
        socket = assign(socket, busy: busy)

        case result do
          {:ok, {:error, :sign_in}} -> {:noreply, needs_trade(socket, op)}
          result -> {:noreply, socket |> settled(op) |> wrote(op, result)}
        end
    end
  end

  # One trade at a time: what needs one while a trade is under way waits for it.
  defp needs_trade(socket, op) do
    %{waiting: waiting, again: again} = socket.assigns

    cond do
      MapSet.member?(again, op) -> assign(socket, control: :ended, waiting: [])
      waiting == [] -> socket |> assign(waiting: [op]) |> push_event("siwa-control:trade", %{})
      true -> assign(socket, waiting: waiting ++ [op])
    end
  end

  # A trade nothing waits for any more, from before the page moved on, changes nothing.
  defp traded(%{assigns: %{waiting: []}} = socket, _outcome), do: socket

  defp traded(socket, "ready") do
    %{waiting: waiting, again: again} = socket.assigns
    socket = assign(socket, waiting: [], again: MapSet.union(again, MapSet.new(waiting)))
    Enum.reduce(waiting, socket, &run(&2, &1))
  end

  # Nothing is tried again by itself; the person's Try again starts afresh.
  defp traded(socket, "unavailable"), do: assign(socket, control: :unavailable, waiting: [])
  defp traded(socket, "busy"), do: assign(socket, control: :busy, waiting: [])
  defp traded(socket, _signed_out), do: assign(socket, control: :ended, waiting: [])

  defp settled(socket, op), do: update(socket, :again, &MapSet.delete(&1, op))

  defp landed(socket, :company),
    do: if(known_company?(socket.assigns), do: run_page(socket), else: socket)

  # Agents go into the stream and out of the read, so the page keeps none of them.
  defp landed(%{assigns: %{agents: %Read{value: %{rows: rows} = page} = read}} = socket, :agents) do
    socket
    |> assign(agents: %{read | value: nil}, next: page.next, names: page.names)
    |> stream(:agents, rows, reset: true)
  end

  defp landed(
         %{assigns: %{more_agents: %Read{value: %{rows: rows} = page} = read}} = socket,
         :more_agents
       ) do
    socket
    |> assign(more_agents: %{read | value: nil}, next: page.next)
    |> stream(:agents, rows)
  end

  defp landed(socket, _name), do: socket

  defp wrote(socket, op, {:ok, {:ok, answer}}), do: done(socket, op, answer)

  defp wrote(
         socket,
         {:create_company, _params},
         {:ok, {:error, %Refusal{code: "customer_exists"}}}
       ),
       do: run(socket, :company)

  # The service says why a cap is too low in its own words; the page says it in
  # its own, with the amounts that apply now.
  defp wrote(
         socket,
         {:set_cap, _cap_cents},
         {:ok,
          {:error,
           %Refusal{status: 422, code: "control_fields_invalid", fields: %{"capCents" => _}}}}
       ),
       do: cap_error(socket, too_low(socket.assigns.company))

  defp wrote(socket, op, {:ok, {:error, %Refusal{status: 422, fields: fields}}})
       when map_size(fields) > 0,
       do: refused_fields(socket, section(op), fields)

  defp wrote(socket, op, {:ok, {:error, %Refusal{status: status} = refusal}}) when status != 503,
    do: notice(socket, section(op), :error, refusal_words(refusal))

  defp wrote(socket, op, _unavailable), do: notice(socket, section(op), :error, @unavailable)

  defp done(socket, {:create_company, _params}, customer) do
    socket =
      socket
      |> update(:drafts, &Map.delete(&1, "company"))
      |> put_company(%{"customer" => customer})

    if socket.assigns.page == :siwa_sites,
      do: run_page(socket),
      else: push_patch(socket, to: ~p"/siwa/sites")
  end

  defp done(socket, {:update_company, _params}, customer) do
    socket
    |> update(:drafts, &Map.delete(&1, "company"))
    |> put_company(%{"customer" => customer})
    |> notice("company", :success, "Saved.")
  end

  defp done(socket, {:set_cap, cap_cents}, company) do
    socket
    |> update(:drafts, &Map.delete(&1, "cap"))
    |> put_company(company)
    |> notice("cap", :success, if(cap_cents, do: "Saved.", else: "Cap removed."))
  end

  defp done(socket, {:create_site, _params}, site) do
    socket
    |> assign(adding: false)
    |> update(:drafts, &Map.delete(&1, "site"))
    |> push_patch(to: ~p"/siwa/sites/#{site["id"]}")
  end

  defp done(socket, {:update_site, id, _params}, site) do
    socket
    |> update(:drafts, &Map.delete(&1, "details"))
    |> put_site(id, &%{&1 | site: site})
    |> notice("details", :success, "Saved.")
  end

  # The key itself goes to the browser and nowhere else.
  defp done(socket, {:make_key, id}, %{"key" => %Secret{value: secret}} = made) do
    key = Map.delete(made, "key")

    socket
    |> assign(revealed: Map.take(key, ["id", "prefix"]))
    |> put_site(id, &%{&1 | keys: [key | &1.keys]})
    |> push_event("siwa-key:reveal", %{key: secret})
  end

  defp done(socket, {:revoke_key, id, key_id}, revoked) do
    socket
    |> update(:revealed, &if(&1 && &1["id"] == key_id, do: nil, else: &1))
    |> put_site(id, fn shown ->
      %{shown | keys: Enum.map(shown.keys, &if(&1["id"] == key_id, do: revoked, else: &1))}
    end)
  end

  defp done(socket, {:archive, _id}, _archived), do: push_patch(socket, to: ~p"/siwa/sites")

  # What a change answered is what a read would show now.
  defp put_read(socket, name, owner, value),
    do: Read.now(socket, name, owner, fn -> {:ok, value} end)

  defp put_company(socket, company) do
    account_id = socket.assigns.account.id

    case socket.assigns.company do
      %Read{owner: ^account_id, value: %{"customer" => _} = shown} ->
        put_read(socket, :company, account_id, Map.merge(shown, company))

      _moved_on ->
        socket
    end
  end

  defp put_site(socket, id, change) do
    case socket.assigns.site do
      %Read{owner: {account_id, ^id} = owner, value: %{site: _, keys: _} = shown} ->
        if account_id == socket.assigns.account.id,
          do: put_read(socket, :site, owner, change.(shown)),
          else: socket

      _moved_on ->
        socket
    end
  end

  defp refused_fields(socket, form, fields) do
    {known, other} = Map.split(fields, Map.get(@fields, form, []))
    socket = update(socket, :errors, &Map.put(&1, form, known))

    if other == %{},
      do: socket,
      else: notice(socket, form, :error, Enum.map_join(other, " ", &field_words/1))
  end

  defp notice(socket, section, tone, words),
    do: update(socket, :notices, &Map.put(&1, section, {tone, words}))

  defp cap_error(socket, words),
    do: update(socket, :errors, &Map.put(&1, "cap", %{"capCents" => [words]}))

  # A cap covers at least the fee this period has reached, rounded up to a whole
  # cent; with no period, the service's least.
  defp too_low(%Read{value: %{"usage" => %{} = usage}}),
    do:
      "Set a cap of at least #{money(least_cap(usage))}, the fee this period has reached so far."

  defp too_low(_no_period), do: "Set a cap of at least #{money(@least_cap)}."

  defp least_cap(nil), do: @least_cap

  defp least_cap(%{"feeCents" => fee}),
    do: fee |> Decimal.round(0, :ceiling) |> Decimal.to_integer()

  defp section({:set_cap, _cap_cents}), do: "cap"
  defp section({:create_company, _params}), do: "company"
  defp section({:update_company, _params}), do: "company"
  defp section({:create_site, _params}), do: "site"
  defp section({:update_site, _id, _params}), do: "details"
  defp section({:make_key, _id}), do: "keys"
  defp section({:revoke_key, _id, _key_id}), do: "keys"
  defp section({:archive, _id}), do: "archive"

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        screen: screen(assigns),
        pending: Map.values(assigns.busy) ++ assigns.waiting
      )

    ~H"""
    <article id="siwa-page" class="account-page siwa-page rg-utility" phx-hook="SiwaControl">
      <P.breadcrumb
        :if={match?({:site, _site, _keys}, @screen)}
        id="siwa-crumbs"
        crumbs={[
          %{label: "Sites", icon: "key-round", patch: ~p"/siwa/sites"},
          %{label: title(@page, @screen), icon: "globe"}
        ]}
      />
      <.page_head title={title(@page, @screen)}>
        <:tip>{tip(@page)}</:tip>
        <:actions :if={match?({:sites, [_ | _]}, @screen) and not @adding}>
          <P.button
            id="siwa-add-site"
            type="button"
            variant="secondary"
            arrow={false}
            phx-click="add_site"
            phx-target={@myself}
          >
            New site
          </P.button>
        </:actions>
      </.page_head>

      <%= case @screen do %>
        <% :signed_out -> %>
          <Regent.Account.signed_out id="siwa-signed-out" reason={@signed_out_reason}>
            <:sign_in>
              <P.button type="button" data-account-target="sign-in">Sign in</P.button>
            </:sign_in>
          </Regent.Account.signed_out>
        <% :ended -> %>
          <P.empty_state id="siwa-ended" title="Sign in" class="siwa-state">
            Your SIWA sign-in has ended. Sign in again to keep working on your sites.
            <:action>
              <div class="siwa-actions">
                <P.button type="button" data-account-target="sign-in">Sign in</P.button>
                <.retry myself={@myself} />
              </div>
            </:action>
          </P.empty_state>
        <% :unavailable -> %>
          <P.empty_state id="siwa-unavailable" title="Unavailable" class="siwa-state">
            SIWA isn't available right now. Try again later.
            <:action><.retry myself={@myself} /></:action>
          </P.empty_state>
        <% :busy -> %>
          <P.empty_state id="siwa-busy" title="Busy" class="siwa-state">
            Too many tries in a short time. Wait a moment, then try again.
            <:action><.retry myself={@myself} /></:action>
          </P.empty_state>
        <% :loading -> %>
          <P.waiting id="siwa-loading" class="siwa-waiting"><span></span></P.waiting>
        <% {:refused, refusal} -> %>
          <P.empty_state id="siwa-refused" title={refusal_title(refusal)} class="siwa-state">
            {refusal_words(refusal)}
            <:action :if={@page == :siwa_site}>
              <.link patch={~p"/siwa/sites"} class="siwa-link">All sites</.link>
            </:action>
          </P.empty_state>
        <% :setup -> %>
          <section class="account-panel" aria-labelledby="siwa-company-title">
            <h2 id="siwa-company-title">Company</h2>
            <p class="rg-muted">Name your company to start adding sites.</p>
            <.company_form
              form={form(@drafts, "company", %{"name" => ""})}
              errors={@errors["company"]}
              notice={@notices["company"]}
              event="create_company"
              busy={pending?(@pending, :create_company)}
              myself={@myself}
            >
              Continue
            </.company_form>
          </section>
        <% {:overview, customer, usage} -> %>
          <.overview
            customer={customer}
            usage={usage}
            agents={@agents}
            more={@more_agents}
            rows={@streams.agents}
            next={@next}
            drafts={@drafts}
            errors={@errors}
            notices={@notices}
            pending={@pending}
            myself={@myself}
          />
        <% {:settings, customer} -> %>
          <.settings
            customer={customer}
            owner={PublicIdentity.person(@account)}
            drafts={@drafts}
            errors={@errors}
            notices={@notices}
            pending={@pending}
            myself={@myself}
          />
        <% {:sites, sites} -> %>
          <.sites
            sites={sites}
            adding={@adding}
            drafts={@drafts}
            errors={@errors}
            notices={@notices}
            pending={@pending}
            myself={@myself}
          />
        <% {:site, site, keys} -> %>
          <.site
            site={site}
            keys={keys}
            revealed={@revealed}
            drafts={@drafts}
            errors={@errors}
            notices={@notices}
            pending={@pending}
            myself={@myself}
          />
      <% end %>
    </article>
    """
  end

  # What the page shows, from the sign-in, the trade and its reads.
  defp screen(%{account: nil}), do: :signed_out
  defp screen(%{control: :ended}), do: :ended
  defp screen(%{control: :unavailable}), do: :unavailable
  defp screen(%{control: :busy}), do: :busy

  defp screen(assigns) do
    case view(assigns.company) do
      {:ready, %{"customer" => nil}} -> :setup
      {:ready, company} -> page_screen(assigns, company)
      other -> other
    end
  end

  defp page_screen(%{page: :siwa_overview}, %{"customer" => customer, "usage" => usage}),
    do: {:overview, customer, usage}

  defp page_screen(%{page: :siwa_settings}, %{"customer" => customer}),
    do: {:settings, customer}

  defp page_screen(%{page: :siwa_sites, sites: sites}, _customer) do
    case view(sites) do
      {:ready, sites} -> {:sites, sites}
      other -> other
    end
  end

  defp page_screen(%{page: :siwa_site, site: site}, _customer) do
    case view(site) do
      {:ready, %{site: site, keys: keys}} -> {:site, site, keys}
      other -> other
    end
  end

  # A read shows its value once it has one, also while it is read again.
  defp view(%Read{value: {:refused, refusal}}), do: {:refused, refusal}
  defp view(%Read{state: :error}), do: :unavailable
  defp view(%Read{read_at: nil}), do: :loading
  defp view(%Read{value: value}), do: {:ready, value}

  defp title(:siwa_overview, _screen), do: "Overview"
  defp title(:siwa_sites, _screen), do: "Sites"
  defp title(:siwa_settings, _screen), do: "Settings"
  defp title(:siwa_site, {:site, site, _keys}), do: site["name"]
  defp title(:siwa_site, _screen), do: "Site"

  defp tip(:siwa_overview),
    do: "Your company's billing period: the agents counted, the fee so far and your cap."

  defp tip(:siwa_settings), do: "Your company's name, its owner and where to get help."
  defp tip(:siwa_site), do: "This site's audience, origins and keys, and how to check an agent."

  defp tip(_sites),
    do: "The sites where agents sign in with SIWA. Each has its own audience, origins and keys."

  attr :myself, :any, required: true

  defp retry(assigns) do
    ~H"""
    <P.button type="button" variant="secondary" arrow={false} phx-click="retry" phx-target={@myself}>
      Try again
    </P.button>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :errors, :map, default: nil
  attr :notice, :any, default: nil
  attr :event, :string, required: true
  attr :busy, :boolean, required: true
  attr :myself, :any, required: true
  slot :inner_block, required: true

  defp company_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="siwa-company-form"
      class="siwa-form"
      phx-change="draft"
      phx-submit={@event}
      phx-target={@myself}
    >
      <P.field
        :let={field}
        id="siwa-company-name"
        label="Name"
        errors={field_errors(@errors, "name")}
      >
        <input
          id={field.id}
          name={@form[:name].name}
          value={@form[:name].value}
          autocomplete="organization"
          phx-debounce="blur"
          aria-invalid={field.aria_invalid}
          aria-describedby={field.described_by}
        />
        <:hint>Up to 100 characters.</:hint>
      </P.field>
      <div class="siwa-actions">
        <P.button type="submit" disabled={@busy} phx-disable-with="Saving…">
          {render_slot(@inner_block)}
        </P.button>
      </div>
      <.notice id="siwa-company-notice" notice={@notice} />
    </.form>
    """
  end

  attr :customer, :map, required: true

  attr :usage, :map,
    default: nil,
    doc: "the billing period running now; nil before billing starts"

  attr :agents, Read, required: true
  attr :more, Read, required: true
  attr :rows, :any, required: true, doc: "the agents stream"
  attr :next, :string, default: nil
  attr :drafts, :map, required: true
  attr :errors, :map, required: true
  attr :notices, :map, required: true
  attr :pending, :list, required: true
  attr :myself, :any, required: true

  defp overview(assigns) do
    ~H"""
    <section
      :if={is_nil(@usage)}
      id="siwa-billing"
      class="account-panel siwa-card"
      aria-labelledby="siwa-billing-title"
    >
      <div class="siwa-head">
        <h2 id="siwa-billing-title">Billing</h2>
        <P.status>Not started</P.status>
      </div>
      <p class="rg-muted">
        Your sandbox sites work now, and their agents are never counted. Once billing starts, each
        agent that signs in to one of your production sites counts once a period, and this page
        shows the period, its agents and the fee so far.
      </p>
      <div class="siwa-actions">
        <.link patch={~p"/siwa/sites"} class="rg-button rg-button--secondary rg-button--no-arrow">
          <span class="rg-button__label">View sites</span>
        </.link>
      </div>
    </section>

    <section
      :if={@usage}
      id="siwa-usage"
      class="account-panel siwa-usage"
      aria-labelledby="siwa-usage-title"
    >
      <h2 id="siwa-usage-title">Usage</h2>
      <p class="rg-muted">
        This period runs <span id="siwa-period" class="siwa-period">{period(@usage)}</span>.
        Dates are in UTC.
      </p>
      <dl
        id="siwa-stats"
        class="siwa-stats"
        phx-hook="MotionCount"
        data-variant={Motion.standard("count")}
      >
        <div class="siwa-card siwa-stat siwa-stat--wide">
          <dt>Agents</dt>
          <dd>
            <P.figure
              id="siwa-agents-count"
              class="siwa-stat__value"
              value={count(@usage["activeAgents"])}
            />
            <span class="siwa-stat__note">{included(@usage)}</span>
            <span class="siwa-meter" aria-hidden="true">
              <span style={"--siwa-used: #{used(@usage)}%"}></span>
            </span>
          </dd>
        </div>
        <div class="siwa-card siwa-stat">
          <dt>Fee</dt>
          <dd>
            <P.figure id="siwa-fee" class="siwa-stat__value" value={money(@usage["feeCents"])} />
            <span class="siwa-stat__note">So far, before tax</span>
          </dd>
        </div>
        <div class="siwa-card siwa-stat">
          <dt>Cap</dt>
          <dd>
            <P.figure
              :if={@customer["capCents"]}
              id="siwa-cap"
              class="siwa-stat__value"
              value={money(@customer["capCents"])}
            />
            <span :if={is_nil(@customer["capCents"])} id="siwa-cap" class="siwa-stat__value">
              None
            </span>
            <span class="siwa-stat__note">{reach(@customer, @usage)}</span>
          </dd>
        </div>
      </dl>
    </section>

    <section id="siwa-cap-panel" class="account-panel" aria-labelledby="siwa-cap-title">
      <h2 id="siwa-cap-title">Cap</h2>
      <p class="rg-muted">
        The most your SIWA fees can reach in one billing period, before tax. Once they reach it, new
        agents can't sign in to your production sites until the next period. Agents already counted
        still can.
      </p>
      <.form
        :let={cap}
        for={form(@drafts, "cap", %{"amount" => dollars(@customer["capCents"])})}
        id="siwa-cap-form"
        class="siwa-form"
        phx-change="draft"
        phx-submit="set_cap"
        phx-target={@myself}
      >
        <P.field :let={field} id="siwa-cap-amount" label="Amount" errors={cap_errors(@errors)}>
          <span class="siwa-money">
            <span class="siwa-money__sign" aria-hidden="true">$</span>
            <input
              id={field.id}
              name={cap[:amount].name}
              value={cap[:amount].value}
              inputmode="decimal"
              autocomplete="off"
              placeholder="No cap"
              phx-debounce="blur"
              aria-invalid={field.aria_invalid}
              aria-describedby={field.described_by}
            />
          </span>
          <:hint>In US dollars, at least {money(least_cap(@usage))}.</:hint>
        </P.field>
        <div class="siwa-actions">
          <P.button type="submit" disabled={pending?(@pending, :set_cap)} phx-disable-with="Saving…">
            Save
          </P.button>
          <P.button
            :if={@customer["capCents"]}
            id="siwa-cap-remove"
            type="button"
            variant="quiet"
            arrow={false}
            disabled={pending?(@pending, :set_cap)}
            phx-click="remove_cap"
            phx-target={@myself}
            data-confirm="Remove the cap? Your SIWA fees then have no limit in a period."
            data-confirm-action="Remove"
          >
            Remove cap
          </P.button>
        </div>
        <.notice id="siwa-cap-notice" notice={@notices["cap"]} />
      </.form>
    </section>

    <section
      :if={@usage}
      id="siwa-agents-panel"
      class="account-panel"
      aria-labelledby="siwa-agents-title"
    >
      <h2 id="siwa-agents-title">Agents</h2>
      <p class="rg-muted">
        Each agent counts once a period, from its first sign-in to one of your production sites.
      </p>
      <p :if={@usage["activeAgents"] == 0} id="siwa-agents-none" class="rg-muted">
        No agents yet this period.
      </p>
      <.agent_list
        :if={@usage["activeAgents"] > 0}
        agents={@agents}
        more={@more}
        rows={@rows}
        next={@next}
        myself={@myself}
      />
    </section>
    """
  end

  attr :agents, Read, required: true
  attr :more, Read, required: true
  attr :rows, :any, required: true
  attr :next, :string, default: nil
  attr :myself, :any, required: true

  defp agent_list(assigns) do
    ~H"""
    <P.waiting id="siwa-agents-box" state={box(@agents)} class="siwa-agents-box">
      <div class="siwa-agents__head" aria-hidden="true">
        <span>Agent</span>
        <span>Chain</span>
        <span>Site</span>
        <span>First seen</span>
      </div>
      <ul id="siwa-agents" class="siwa-agents" phx-update="stream">
        <li :for={{dom_id, agent} <- @rows} id={dom_id} class="siwa-agents__row">
          <P.address
            id={"#{dom_id}-wallet"}
            class="siwa-agents__agent"
            address={agent.address}
            chain={agent.chain}
          />
          <span class="siwa-agents__cell">
            <span class="visually-hidden">Chain</span>
            {agent.chain_name}
          </span>
          <span class="siwa-agents__cell">
            <span class="visually-hidden">Site</span>
            <bdi :if={agent.site}>{agent.site}</bdi>
            <span :if={is_nil(agent.site)} class="rg-muted">Archived site</span>
          </span>
          <span class="siwa-agents__cell">
            <span class="visually-hidden">First seen</span>
            <time datetime={DateTime.to_iso8601(agent.at)}>{date(agent.at)}</time>
          </span>
        </li>
      </ul>
      <:retry>
        <P.button
          type="button"
          variant="secondary"
          arrow={false}
          phx-click="list_agents"
          phx-target={@myself}
        >
          Try again
        </P.button>
      </:retry>
    </P.waiting>
    <div :if={@next && box(@agents) == :ready} class="siwa-actions">
      <P.button
        id="siwa-agents-more"
        type="button"
        variant="secondary"
        arrow={false}
        disabled={@more.state == :loading}
        phx-click="more_agents"
        phx-target={@myself}
      >
        More
      </P.button>
    </div>
    <P.notice :if={@more.state in [:error, :stale]} id="siwa-agents-failed" tone="error">
      The next agents couldn't be loaded. Press More to try again.
    </P.notice>
    <.notice id="siwa-agents-notice" notice={refusal(@agents) || refusal(@more)} />
    """
  end

  # The list's box waits for the first page, and says when it couldn't be read,
  # with Try again in place of rows from before.
  defp box(%Read{state: state}) when state in [:idle, :loading], do: :loading
  defp box(%Read{state: state}) when state in [:error, :stale], do: :error
  defp box(%Read{}), do: :ready

  defp refusal(%Read{value: {:refused, refusal}}), do: {:error, refusal_words(refusal)}
  defp refusal(%Read{}), do: nil

  attr :customer, :map, required: true
  attr :owner, :map, required: true, doc: "`AshTemplate.PublicIdentity.person/1`"
  attr :drafts, :map, required: true
  attr :errors, :map, required: true
  attr :notices, :map, required: true
  attr :pending, :list, required: true
  attr :myself, :any, required: true

  defp settings(assigns) do
    ~H"""
    <section class="account-panel" aria-labelledby="siwa-company-title">
      <h2 id="siwa-company-title">Company</h2>
      <.company_form
        form={form(@drafts, "company", %{"name" => @customer["name"]})}
        errors={@errors["company"]}
        notice={@notices["company"]}
        event="update_company"
        busy={pending?(@pending, :update_company)}
        myself={@myself}
      >
        Save
      </.company_form>
    </section>

    <section class="account-panel account-details" aria-labelledby="siwa-owner-title">
      <h2 id="siwa-owner-title">Owner</h2>
      <dl>
        <div :if={@owner.name}>
          <dt>Name</dt>
          <dd id="siwa-owner-name"><bdi>{@owner.name}</bdi></dd>
        </div>
        <div :if={@owner.wallet}>
          <dt>Wallet</dt>
          <dd>
            <P.address id="siwa-owner-wallet" address={@owner.wallet} label={@owner.ens_name} />
          </dd>
        </div>
      </dl>
    </section>

    <section class="account-panel" aria-labelledby="siwa-support-title">
      <h2 id="siwa-support-title">Support</h2>
      <p>
        Questions about SIWA? Write to <a
          id="siwa-support"
          class="siwa-link"
          href="mailto:build@regents.sh"
        >build@regents.sh</a>.
      </p>
    </section>
    """
  end

  attr :sites, :list, required: true
  attr :adding, :boolean, required: true
  attr :drafts, :map, required: true
  attr :errors, :map, required: true
  attr :notices, :map, required: true
  attr :pending, :list, required: true
  attr :myself, :any, required: true

  defp sites(assigns) do
    ~H"""
    <section :if={@sites != []} class="account-panel" aria-labelledby="page-title">
      <ul id="siwa-sites" class="siwa-sites">
        <li class="siwa-sites__head" aria-hidden="true">
          <span>Name</span>
          <span>Audience</span>
          <span>Environment</span>
          <span>Proof</span>
        </li>
        <li :for={site <- @sites} id={"siwa-site-#{site["id"]}"}>
          <.link patch={~p"/siwa/sites/#{site["id"]}"} class="siwa-sites__row">
            <span class="siwa-sites__name">{site["name"]}</span>
            <span class="siwa-sites__cell">
              <span class="siwa-sites__label">Audience</span>
              <code>{site["audience"]}</code>
            </span>
            <span class="siwa-sites__cell">
              <span class="siwa-sites__label">Environment</span>
              <.environment site={site} />
            </span>
            <span class="siwa-sites__cell">
              <span class="siwa-sites__label">Proof</span>
              <.proof site={site} />
            </span>
          </.link>
        </li>
      </ul>
    </section>

    <section
      :if={@adding or @sites == []}
      class="account-panel"
      aria-labelledby="siwa-new-site-title"
    >
      <h2 id="siwa-new-site-title">New site</h2>
      <p :if={@sites == []} class="rg-muted">Add your first site. Agents sign in to it with SIWA.</p>
      <.site_form
        form={form(@drafts, "site", %{"environment" => "sandbox"})}
        errors={@errors["site"]}
        notice={@notices["site"]}
        busy={pending?(@pending, :create_site)}
        cancel={@sites != []}
        myself={@myself}
      />
    </section>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :errors, :map, default: nil
  attr :notice, :any, default: nil
  attr :busy, :boolean, required: true
  attr :cancel, :boolean, required: true
  attr :myself, :any, required: true

  defp site_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="siwa-site-form"
      class="siwa-form"
      phx-change="draft"
      phx-submit="create_site"
      phx-target={@myself}
    >
      <P.field :let={field} id="siwa-site-name" label="Name" errors={field_errors(@errors, "name")}>
        <input
          id={field.id}
          name={@form[:name].name}
          value={@form[:name].value}
          autocomplete="off"
          phx-debounce="blur"
          aria-invalid={field.aria_invalid}
          aria-describedby={field.described_by}
        />
        <:hint>What your team calls it, up to 100 characters.</:hint>
      </P.field>
      <P.field
        :let={field}
        id="siwa-site-audience"
        label="Audience"
        errors={field_errors(@errors, "audience")}
      >
        <input
          id={field.id}
          name={@form[:audience].name}
          value={@form[:audience].value}
          autocomplete="off"
          autocapitalize="none"
          spellcheck="false"
          phx-debounce="blur"
          aria-invalid={field.aria_invalid}
          aria-describedby={field.described_by}
        />
        <:hint>
          The name agents sign in for: 1 to 64 lowercase letters, digits, - or _.
          It can't change, and it stays taken if you archive the site.
        </:hint>
      </P.field>
      <P.field
        :let={field}
        id="siwa-site-environment"
        label="Environment"
        errors={field_errors(@errors, "environment")}
      >
        <select
          id={field.id}
          name={@form[:environment].name}
          aria-invalid={field.aria_invalid}
          aria-describedby={field.described_by}
        >
          <option value="sandbox" selected={@form[:environment].value == "sandbox"}>Sandbox</option>
          <option value="production" selected={@form[:environment].value == "production"}>
            Production
          </option>
        </select>
        <:hint>Sandbox is for a site on your own computer. It can't change later.</:hint>
      </P.field>
      <.origins_field form={@form} id="siwa-site-origins" errors={@errors} />
      <div class="siwa-actions">
        <P.button id="siwa-site-submit" type="submit" disabled={@busy} phx-disable-with="Adding…">
          Add site
        </P.button>
        <P.button
          :if={@cancel}
          type="button"
          variant="quiet"
          arrow={false}
          phx-click="cancel_site"
          phx-target={@myself}
        >
          Cancel
        </P.button>
      </div>
      <.notice id="siwa-site-notice" notice={@notice} />
    </.form>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :id, :string, required: true
  attr :errors, :map, default: nil

  defp origins_field(assigns) do
    ~H"""
    <P.field :let={field} id={@id} label="Origins" errors={field_errors(@errors, "origins")}>
      <textarea
        id={field.id}
        name={@form[:origins].name}
        rows="3"
        autocapitalize="none"
        spellcheck="false"
        phx-debounce="blur"
        aria-invalid={field.aria_invalid}
        aria-describedby={field.described_by}
      >{Phoenix.HTML.Form.normalize_value("textarea", @form[:origins].value)}</textarea>
      <:hint>
        The addresses your site runs at, one a line, up to 10. Sandbox: http://localhost and a
        port, such as http://localhost:4000. Production: https:// and a host, such as
        https://example.com.
      </:hint>
    </P.field>
    """
  end

  attr :site, :map, required: true
  attr :keys, :list, required: true
  attr :revealed, :map, default: nil
  attr :drafts, :map, required: true
  attr :errors, :map, required: true
  attr :notices, :map, required: true
  attr :pending, :list, required: true
  attr :myself, :any, required: true

  defp site(assigns) do
    ~H"""
    <section class="account-panel account-details" aria-labelledby="siwa-summary-title">
      <h2 id="siwa-summary-title">Summary</h2>
      <dl>
        <div>
          <dt>Audience</dt>
          <dd class="siwa-inline">
            <code id="siwa-audience">{@site["audience"]}</code>
            <P.copy_icon id="siwa-audience-copy" text={@site["audience"]} label="Copy the audience" />
          </dd>
        </div>
        <div>
          <dt>Environment</dt>
          <dd><.environment site={@site} /></dd>
        </div>
        <div>
          <dt>Proof</dt>
          <dd><.proof site={@site} /></dd>
        </div>
        <div>
          <dt>Made</dt>
          <dd>{day(@site["createdAt"])}</dd>
        </div>
      </dl>
    </section>

    <section class="account-panel" aria-labelledby="siwa-details-title">
      <h2 id="siwa-details-title">Details</h2>
      <.form
        :let={details}
        for={form(@drafts, "details", %{"name" => @site["name"], "origins" => lines(@site)})}
        id="siwa-details-form"
        class="siwa-form"
        phx-change="draft"
        phx-submit="update_site"
        phx-target={@myself}
      >
        <P.field
          :let={field}
          id="siwa-details-name"
          label="Name"
          errors={field_errors(@errors["details"], "name")}
        >
          <input
            id={field.id}
            name={details[:name].name}
            value={details[:name].value}
            autocomplete="off"
            phx-debounce="blur"
            aria-invalid={field.aria_invalid}
            aria-describedby={field.described_by}
          />
        </P.field>
        <.origins_field form={details} id="siwa-details-origins" errors={@errors["details"]} />
        <P.notice :if={@site["environment"] == "production"} id="siwa-proof-warning" tone="warning">
          Changing a production site's origins sets its proof back to Not proven.
        </P.notice>
        <div class="siwa-actions">
          <P.button
            type="submit"
            disabled={pending?(@pending, :update_site)}
            phx-disable-with="Saving…"
          >
            Save
          </P.button>
        </div>
        <.notice id="siwa-details-notice" notice={@notices["details"]} />
      </.form>
    </section>

    <section class="account-panel" aria-labelledby="siwa-keys-title">
      <div class="siwa-head">
        <h2 id="siwa-keys-title">Keys</h2>
        <P.button
          id="siwa-make-key"
          type="button"
          variant="secondary"
          arrow={false}
          disabled={pending?(@pending, :make_key)}
          phx-click="make_key"
          phx-target={@myself}
        >
          New key
        </P.button>
      </div>
      <p class="rg-muted">Keys let your site's server talk to SIWA. Up to 5 can be in use at once.</p>
      <div :if={@revealed} id="siwa-key-reveal" class="siwa-reveal">
        <P.notice tone="warning">Copy this key now. You won't see it again.</P.notice>
        <code id="siwa-key-value" class="siwa-reveal__key" phx-update="ignore"></code>
        <div class="siwa-actions">
          <P.copy_button id="siwa-key-copy" target="siwa-key-value">Copy key</P.copy_button>
          <P.button
            id="siwa-key-done"
            type="button"
            variant="quiet"
            arrow={false}
            phx-click="hide_key"
            phx-target={@myself}
          >
            Done
          </P.button>
        </div>
      </div>
      <ul :if={@keys != []} id="siwa-keys" class="siwa-keys">
        <li :for={key <- @keys} id={"siwa-key-#{key["id"]}"} class="siwa-keys__row">
          <code class="siwa-keys__prefix">{key["prefix"]}…</code>
          <span class="siwa-keys__dates rg-muted">
            Made {day(key["createdAt"])}<span :if={key["revokedAt"]}>, revoked {day(key["revokedAt"])}</span>
          </span>
          <P.status :if={key["revokedAt"]}>Revoked</P.status>
          <P.status :if={is_nil(key["revokedAt"])} tone="success">In use</P.status>
          <P.button
            :if={is_nil(key["revokedAt"])}
            id={"siwa-revoke-#{key["id"]}"}
            type="button"
            variant="quiet"
            arrow={false}
            disabled={{:revoke_key, @site["id"], key["id"]} in @pending}
            phx-click="revoke_key"
            phx-value-id={key["id"]}
            phx-target={@myself}
            aria-label={"Revoke the key #{key["prefix"]}"}
            data-confirm={"Revoke the key #{key["prefix"]}…? Your server can't use it again."}
            data-confirm-action="Revoke"
          >
            Revoke
          </P.button>
        </li>
      </ul>
      <p :if={@keys == []} class="rg-muted">No keys yet.</p>
      <.notice id="siwa-keys-notice" notice={@notices["keys"]} />
    </section>

    <section class="account-panel" aria-labelledby="siwa-setup-title">
      <h2 id="siwa-setup-title">Setup</h2>
      <p class="rg-muted">
        When an agent signs a request to your site, send its parts to SIWA, with each header copied
        from the agent's request. SIWA answers with the agent's wallet once the signature checks out.
      </p>
      <pre class="siwa-code" tabindex="0" aria-label="Setup example"><code id="siwa-setup-code">{example(@site)}</code></pre>
      <div class="siwa-actions">
        <P.copy_button id="siwa-setup-copy" target="siwa-setup-code">Copy example</P.copy_button>
      </div>
    </section>

    <section class="account-panel" aria-labelledby="siwa-archive-title">
      <h2 id="siwa-archive-title">Archive</h2>
      <p class="rg-muted">
        Archiving removes this site and stops its keys at once. Its audience, <code>{@site["audience"]}</code>, stays taken: no site can use it again.
      </p>
      <div class="siwa-actions">
        <P.button
          id="siwa-archive"
          type="button"
          variant="secondary"
          arrow={false}
          disabled={pending?(@pending, :archive)}
          phx-click="archive"
          phx-target={@myself}
          data-confirm={"Archive #{@site["name"]}? Its keys stop working at once, and its audience #{@site["audience"]} stays taken for good."}
          data-confirm-action="Archive"
        >
          Archive site
        </P.button>
      </div>
      <.notice id="siwa-archive-notice" notice={@notices["archive"]} />
    </section>
    """
  end

  attr :site, :map, required: true

  defp environment(assigns) do
    ~H"""
    <P.status :if={@site["environment"] == "production"} tone="info">Production</P.status>
    <P.status :if={@site["environment"] != "production"}>Sandbox</P.status>
    """
  end

  attr :site, :map, required: true

  defp proof(assigns) do
    ~H"""
    <%= case @site["originProof"] do %>
      <% "verified" -> %>
        <P.status tone="success">Proven</P.status>
      <% "unverified" -> %>
        <P.status tone="warning">Not proven</P.status>
      <% nil -> %>
        <span class="rg-muted">Not needed</span>
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :notice, :any, default: nil

  defp notice(%{notice: nil} = assigns), do: ~H""

  defp notice(%{notice: {tone, words}} = assigns) do
    assigns = assign(assigns, tone: Atom.to_string(tone), words: words)

    ~H"""
    <P.notice id={@id} tone={@tone}>{@words}</P.notice>
    """
  end

  # The person's own typing while they have any, otherwise what is saved.
  defp form(drafts, name, saved), do: to_form(Map.get(drafts, name, saved), as: name)

  defp lines(site), do: Enum.join(site["origins"], "\n")

  defp pending?(pending, kind), do: Enum.any?(pending, &(is_tuple(&1) and elem(&1, 0) == kind))

  defp field_errors(nil, _field), do: []

  defp field_errors(errors, field),
    do: Enum.map(Map.get(errors, field, []), &"#{@labels[field]} #{&1}.")

  defp field_words({field, reasons}),
    do: Enum.map_join(reasons, " ", &"#{String.capitalize(field)} #{&1}.")

  defp refusal_title(%Refusal{status: 404}), do: "Not found"
  defp refusal_title(_refusal), do: "Not allowed"

  defp refusal_words(%Refusal{code: code, message: message, hint: hint}) do
    Map.get_lazy(@refusals, code, fn ->
      [message, hint] |> Enum.reject(&is_nil/1) |> Enum.map_join(" ", &sentence/1)
    end)
  end

  defp sentence(words) do
    {first, rest} = String.split_at(String.trim(words), 1)
    words = String.upcase(first) <> rest
    if String.ends_with?(words, [".", "!", "?"]), do: words, else: words <> "."
  end

  defp day(iso) do
    {:ok, at, _offset} = DateTime.from_iso8601(iso)
    date(at)
  end

  defp date(at), do: Calendar.strftime(at, "%-d %b %Y")

  # A period's first and last days; it ends the moment its last day does.
  defp period(%{"periodStartsAt" => starts, "periodEndsAt" => ends}) do
    {:ok, starts, _offset} = DateTime.from_iso8601(starts)
    {:ok, ends, _offset} = DateTime.from_iso8601(ends)
    last = DateTime.add(ends, -1, :second)

    cond do
      {starts.year, starts.month} == {last.year, last.month} -> "#{starts.day}–#{date(last)}"
      starts.year == last.year -> "#{Calendar.strftime(starts, "%-d %b")} – #{date(last)}"
      true -> "#{date(starts)} – #{date(last)}"
    end
  end

  defp count(number), do: number |> Integer.to_string() |> RegentFormat.add_delimiters()

  defp included(%{"activeAgents" => counted, "includedAgents" => included})
       when counted > included,
       do: "#{count(counted - included)} past the #{count(included)} included"

  defp included(%{"includedAgents" => included}), do: "Of #{count(included)} included"

  defp used(%{"activeAgents" => counted, "includedAgents" => included}),
    do: min(100, div(counted * 100, included))

  defp reach(%{"capCents" => nil}, _usage), do: "No limit on fees"
  defp reach(_customer, %{"maxAgents" => most}), do: "Up to #{count(most)} agents"

  # Dollars from cents, exactly: a fee with a tenth of a cent shows all three places.
  defp money(cents) when is_integer(cents), do: money(Decimal.new(cents))

  defp money(cents) do
    places = if Decimal.integer?(cents), do: 2, else: 3

    "$" <>
      (cents
       |> Decimal.div(100)
       |> RegentFormat.decimal_to_string(places)
       |> RegentFormat.add_delimiters())
  end

  defp dollars(nil), do: ""

  defp dollars(cents),
    do: cents |> Decimal.new() |> Decimal.div(100) |> RegentFormat.decimal_to_string(2)

  defp cap_errors(%{"cap" => %{"capCents" => words}}), do: words
  defp cap_errors(_errors), do: []

  # What a site's server sends SIWA to check a signed request, for the host of
  # the site's first origin.
  defp example(site) do
    authority = site["origins"] |> List.first() |> String.split("://", parts: 2) |> List.last()

    """
    POST #{SiwaControl.url()}/api/shared/siwa/http-verify
    content-type: application/json
    x-siwa-audience: #{site["audience"]}

    {
      "method": "GET",
      "path": "/api/example",
      "authority": "#{authority}",
      "headers": {
        "x-siwa-receipt": "…",
        "x-siwa-signature": "…",
        "x-siwa-signature-input": "…",
        "x-key-id": "…",
        "x-timestamp": "…",
        "x-agent-wallet-address": "…",
        "x-agent-chain-id": "…"
      }
    }\
    """
  end
end
