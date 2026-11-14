defmodule AshTemplateWeb.SiwaLive do
  @moduledoc """
  The SIWA pages, where a person runs their company's agent sign-in: Sites
  (`/siwa/sites`), one site with its keys (`/siwa/sites/:site_id`) and Settings
  (`/siwa/settings`). All of it is read from the sign-in service's control API
  (`AshTemplate.SiwaControl`) each time; this site keeps none of it. A person
  with no company names it first, then lands on Sites.

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
  alias AshTemplateWeb.Read
  alias Regent.Primitives, as: P

  @reads [:company, :sites, :site]
  @forms ~w(company site details)
  @fields %{
    "company" => ~w(name),
    "site" => ~w(name audience environment origins),
    "details" => ~w(name origins)
  }
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

  defp fresh(socket) do
    assign(socket,
      control: :ready,
      waiting: [],
      again: MapSet.new(),
      busy: %{},
      adding: false,
      drafts: %{},
      errors: %{},
      notices: %{},
      revealed: nil
    )
  end

  # Settings reads the company each time; the other pages read it once.
  defp begin(%{assigns: %{owner: nil}} = socket), do: socket

  defp begin(socket) do
    if socket.assigns.page != :siwa_settings and known_company?(socket.assigns),
      do: run_page(socket),
      else: run(socket, :company)
  end

  defp known_company?(%{company: %Read{owner: id, value: %{"id" => _}}, account: %{id: id}}),
    do: true

  defp known_company?(_assigns), do: false

  defp run_page(%{assigns: %{page: :siwa_sites}} = socket), do: run(socket, :sites)
  defp run_page(%{assigns: %{page: :siwa_site}} = socket), do: run(socket, :site)
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

  defp name(params), do: Map.take(params, ["name"])

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

  defp ctx(%{lease: lease, account: account, site_id: site_id}),
    do: %{topic: SessionAuthority.topic(lease.lineage), account_id: account.id, site_id: site_id}

  defp read_owner(:site, ctx), do: {ctx.account_id, ctx.site_id}
  defp read_owner(_name, ctx), do: ctx.account_id

  # A refusal is something to show, not a read that failed; only a service that
  # did not answer, or says it cannot, fails the read.
  defp read(:company, ctx) do
    ctx
    |> call(&SiwaControl.account/1)
    |> then(&with({:ok, %{"customer" => customer}} <- &1, do: {:ok, customer}))
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

  defp landed(socket, :company) do
    if socket.assigns.page != :siwa_settings and known_company?(socket.assigns),
      do: run_page(socket),
      else: socket
  end

  defp landed(socket, _name), do: socket

  defp wrote(socket, op, {:ok, {:ok, answer}}), do: done(socket, op, answer)

  defp wrote(
         socket,
         {:create_company, _params},
         {:ok, {:error, %Refusal{code: "customer_exists"}}}
       ),
       do: run(socket, :company)

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
      |> put_read(:company, socket.assigns.account.id, customer)

    if socket.assigns.page == :siwa_sites,
      do: run_page(socket),
      else: push_patch(socket, to: ~p"/siwa/sites")
  end

  defp done(socket, {:update_company, _params}, customer) do
    socket
    |> update(:drafts, &Map.delete(&1, "company"))
    |> put_read(:company, socket.assigns.account.id, customer)
    |> notice("company", :success, "Saved.")
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
      {:ready, nil} -> :setup
      {:ready, customer} -> page_screen(assigns, customer)
      other -> other
    end
  end

  defp page_screen(%{page: :siwa_settings}, customer), do: {:settings, customer}

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

  defp title(:siwa_sites, _screen), do: "Sites"
  defp title(:siwa_settings, _screen), do: "Settings"
  defp title(:siwa_site, {:site, site, _keys}), do: site["name"]
  defp title(:siwa_site, _screen), do: "Site"

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
    Calendar.strftime(at, "%-d %b %Y")
  end

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
