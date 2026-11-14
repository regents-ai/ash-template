defmodule AshTemplate.WalkControl do
  @moduledoc """
  The browser walk's SIWA control API (`AshTemplate.SiwaControl`), answered in
  this server's memory for the run (`AshTemplate.WalkOffline`) under the
  service's own rules and in its own shapes: each person's company and its cap,
  its billing period and the agents counted in it, its sites and each site's
  keys, at most five of them in use.

  The identity token of the Privy pair a page trades is taken as the person's
  DID, and the token it gets back names them. The access token
  `walk-unavailable` is answered as a service whose control API is off.

  A person starts with nothing, as a new company has no billing period, except
  one whose DID starts `did:privy:browser-walk-siwa-billed-`: their company is
  already billed, with a production site, an archived one and a period this UTC
  month that has counted more agents than it includes.
  """

  @base "/api/control/v1/"
  @billed "did:privy:browser-walk-siwa-billed-"
  @max_keys 5

  # The service's price: $99 a period covers the first 1,000 agents and each one
  # after adds $0.099, in tenths of a cent. A cap is in whole cents.
  @included_agents 1_000
  @base_tenths 99_000
  @agent_tenths 99
  @least_cap 9_900
  @most_cap 2_147_483_647
  @billed_agents 1_204
  @default_page 50
  @most_page 200
  @service_audiences ~w(agent-book agent-link)
  @audience ~r/\A[a-z0-9][a-z0-9_-]{0,63}\z/
  @https ~r/\Ahttps:\/\/(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?\z/
  @local ~r/\Ahttp:\/\/localhost:[1-9][0-9]{0,4}\z/
  @off "the control API is not configured on this server"
  @no_token "the control token is missing, not valid or expired"

  @doc "Whether `request` is for the control API at `url`, the walk's SIWA address."
  def control?(%Req.Request{url: url}, siwa_url) do
    "#{url.scheme}://#{url.host}:#{url.port}" == siwa_url and
      String.starts_with?(url.path || "", @base)
  end

  @doc "Answers one request to the control API, as Req's adapter does."
  def run(%Req.Request{} = request) do
    {status, body} = Agent.get_and_update(agent(), &answer(request, &1))
    {request, Req.Response.json(Req.Response.new(status: status), body)}
  end

  # Started by the first request, and kept for the rest of the run.
  defp agent do
    case Agent.start(fn -> %{people: %{}, audiences: MapSet.new()} end, name: __MODULE__) do
      {:ok, agent} -> agent
      {:error, {:already_started, agent}} -> agent
    end
  end

  defp answer(request, state) do
    path = request.url.path |> String.replace_prefix(@base, "") |> String.split("/", trim: true)

    case {bearer(request), request.method, path} do
      {"walk-unavailable", _method, _path} ->
        {refusal(503, "control_not_configured", @off), state}

      {access, :post, ["session"]} ->
        {session(access, Req.Request.get_header(request, "privy-id-token")), state}

      {"walk-control:" <> did, method, path} ->
        state = known(state, did)

        case step(method, path, params(request), did, state) do
          {:ok, status, code, data, state} -> {{status, %{"code" => code, "data" => data}}, state}
          {:error, refusal} -> {refusal, state}
        end

      _no_token ->
        {refusal(401, "control_token_invalid", @no_token), state}
    end
  end

  defp session(access, [did]) when is_binary(access) do
    expires_at = DateTime.utc_now(:second) |> DateTime.add(15, :minute) |> DateTime.to_iso8601()

    {200,
     %{
       "code" => "control_session",
       "data" => %{"token" => "walk-control:" <> did, "expiresAt" => expires_at, "did" => did}
     }}
  end

  defp session(_access, _identity),
    do: refusal(401, "privy_proof_invalid", "the Privy sign-in was not accepted")

  defp step(:get, ["account"], _params, did, state) do
    %{customer: customer, period: period} = person(state, did)

    {:ok, 200, "account", %{"did" => did, "customer" => customer, "usage" => usage(period)},
     state}
  end

  defp step(:put, ["cap"], params, did, state) do
    with {:ok, params} <- only(params, ~w(capCents)),
         {:ok, customer} <- customer(state, did),
         %{period: period} = person(state, did),
         :ok <- valid(cap(params, period)) do
      cap = params["capCents"]
      customer = %{customer | "capCents" => cap, "updatedAt" => now()}
      period = period && %{period | cap: cap}

      {:ok, 200, "cap_updated", %{"customer" => customer, "usage" => usage(period)},
       update_person(state, did, &%{&1 | customer: customer, period: period})}
    end
  end

  # The period's agents, newest first, a page at a time; with no period, none.
  defp step(:get, ["agents"], params, did, state) do
    with {:ok, params} <- only(params, ~w(after limit)),
         {:ok, _customer} <- customer(state, did),
         :ok <- valid(page(params)) do
      offset = if params["after"], do: offset(params["after"]), else: 0
      limit = if params["limit"], do: String.to_integer(params["limit"]), else: @default_page

      {shown, rest} =
        person(state, did).period |> counted() |> Enum.drop(offset) |> Enum.split(limit)

      next = if rest != [], do: Base.url_encode64("#{offset + limit}", padding: false)
      {:ok, 200, "agents", %{"agents" => shown, "next" => next}, state}
    end
  end

  defp step(:post, ["customer"], params, did, state) do
    with {:ok, params} <- only(params, ~w(name)),
         :ok <- valid(name(params)),
         :ok <- no_customer(state, did) do
      at = now()
      name = String.trim(params["name"])

      customer = %{
        "id" => Ecto.UUID.generate(),
        "name" => name,
        "kind" => "paid",
        "capCents" => nil,
        "createdAt" => at,
        "updatedAt" => at
      }

      {:ok, 201, "customer_created", customer,
       update_person(state, did, &%{&1 | customer: customer})}
    end
  end

  defp step(:patch, ["customer"], params, did, state) do
    with {:ok, params} <- only(params, ~w(name)),
         {:ok, customer} <- customer(state, did),
         :ok <- valid(name(params)) do
      customer = %{customer | "name" => String.trim(params["name"]), "updatedAt" => now()}

      {:ok, 200, "customer_updated", customer,
       update_person(state, did, &%{&1 | customer: customer})}
    end
  end

  defp step(:get, ["sites"], _params, did, state) do
    with {:ok, _customer} <- customer(state, did) do
      sites = Enum.filter(person(state, did).sites, &is_nil(&1["archivedAt"]))
      {:ok, 200, "sites", %{"sites" => sites}, state}
    end
  end

  defp step(:post, ["sites"], params, did, state) do
    with {:ok, params} <- only(params, ~w(name audience environment origins)),
         {:ok, _customer} <- customer(state, did),
         :ok <- valid(new_site(params, state.audiences)) do
      at = now()
      environment = params["environment"]

      site = %{
        "id" => Ecto.UUID.generate(),
        "name" => String.trim(params["name"]),
        "audience" => params["audience"],
        "environment" => environment,
        "origins" => params["origins"],
        "originProof" => if(environment == "production", do: "unverified"),
        "archivedAt" => nil,
        "createdAt" => at,
        "updatedAt" => at
      }

      state =
        state
        |> Map.update!(:audiences, &MapSet.put(&1, site["audience"]))
        |> update_person(did, &%{&1 | sites: &1.sites ++ [site]})

      {:ok, 201, "site_created", site, state}
    end
  end

  defp step(:get, ["sites", id], _params, did, state) do
    with {:ok, site} <- site(state, did, id), do: {:ok, 200, "site", site, state}
  end

  defp step(:patch, ["sites", id], params, did, state) do
    with {:ok, params} <- only(params, ~w(name origins)),
         {:ok, site} <- site(state, did, id),
         :ok <- valid(Map.merge(name(params), origins(params, site["environment"]))) do
      moved? = site["environment"] == "production" and params["origins"] != site["origins"]

      site = %{
        site
        | "name" => String.trim(params["name"]),
          "origins" => params["origins"],
          "originProof" => if(moved?, do: "unverified", else: site["originProof"]),
          "updatedAt" => now()
      }

      {:ok, 200, "site_updated", site, put_site(state, did, site)}
    end
  end

  defp step(:delete, ["sites", id], _params, did, state) do
    with {:ok, site} <- site(state, did, id) do
      site = %{site | "archivedAt" => now()}
      {:ok, 200, "site_archived", site, put_site(state, did, site)}
    end
  end

  defp step(:get, ["sites", id, "keys"], _params, did, state) do
    with {:ok, site} <- site(state, did, id),
         do: {:ok, 200, "site_keys", %{"keys" => keys(state, did, site)}, state}
  end

  defp step(:post, ["sites", id, "keys"], _params, did, state) do
    with {:ok, site} <- site(state, did, id),
         :ok <- room_for_key(keys(state, did, site)) do
      label = if site["environment"] == "production", do: "live", else: "test"

      key =
        "siwa_sk_#{label}_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      made = %{
        "id" => Ecto.UUID.generate(),
        "prefix" => binary_part(key, 0, 19),
        "createdAt" => now(),
        "revokedAt" => nil
      }

      state = put_keys(state, did, site, [made | keys(state, did, site)])
      {:ok, 201, "site_key_created", Map.put(made, "key", key), state}
    end
  end

  defp step(:delete, ["sites", id, "keys", key_id], _params, did, state) do
    with {:ok, site} <- site(state, did, id),
         {:ok, key} <- key(keys(state, did, site), key_id) do
      key = %{key | "revokedAt" => key["revokedAt"] || now()}

      keys =
        Enum.map(keys(state, did, site), fn
          %{"id" => ^key_id} -> key
          other -> other
        end)

      {:ok, 200, "site_key_revoked", key, put_keys(state, did, site, keys)}
    end
  end

  defp step(_method, _path, _params, _did, _state),
    do: {:error, refusal(404, "not_found", "no such route")}

  defp person(state, did), do: Map.fetch!(state.people, did)

  # The person a token names, as they start the first time it is used.
  defp known(%{people: people} = state, did) when is_map_key(people, did), do: state

  defp known(state, @billed <> _width = did) do
    %{sites: sites} = billed = billed(did)

    state
    |> Map.update!(:audiences, &Enum.into(sites, &1, fn site -> site["audience"] end))
    |> Map.update!(:people, &Map.put(&1, did, billed))
  end

  defp known(state, did),
    do: put_in(state.people[did], %{customer: nil, sites: [], keys: %{}, period: nil})

  defp billed(@billed <> width = did) do
    at = DateTime.utc_now(:second)
    starts = %{at | day: 1, hour: 0, minute: 0, second: 0}
    ends = starts |> DateTime.to_date() |> Date.shift(month: 1) |> DateTime.new!(~T[00:00:00])
    made = DateTime.to_iso8601(starts)

    customer = %{
      "id" => Ecto.UUID.generate(),
      "name" => "Walk Billed #{String.capitalize(width)}",
      "kind" => "internal",
      "capCents" => nil,
      "createdAt" => made,
      "updatedAt" => made
    }

    live =
      billed_site("Main site", "walk-billed-#{width}", "https://example.com", made, nil)

    archived =
      billed_site("Old site", "walk-billed-old-#{width}", "https://old.example.com", made, made)

    %{
      customer: customer,
      sites: [live, archived],
      keys: %{},
      period: %{
        starts: starts,
        ends: ends,
        cap: nil,
        agents: billed_agents(did, starts, at, [live["id"], archived["id"]])
      }
    }
  end

  defp billed_site(name, audience, origin, made, archived) do
    %{
      "id" => Ecto.UUID.generate(),
      "name" => name,
      "audience" => audience,
      "environment" => "production",
      "origins" => [origin],
      "originProof" => "verified",
      "archivedAt" => archived,
      "createdAt" => made,
      "updatedAt" => archived || made
    }
  end

  # Agents first seen across the period so far, newest first: every fifth on
  # Ethereum, the rest on Base, and every seventh first seen at the archived site.
  defp billed_agents(did, starts, at, [live, archived]) do
    span = DateTime.diff(at, starts)

    for n <- @billed_agents..1//-1 do
      wallet = :crypto.hash(:sha256, "#{did}:#{n}") |> binary_part(0, 20) |> Base.encode16(case: :lower)

      %{
        "subject" => "eip155:#{if rem(n, 5) == 0, do: 1, else: 8453}:0x#{wallet}",
        "firstVerifiedAt" =>
          starts |> DateTime.add(div(span * n, @billed_agents + 1)) |> DateTime.to_iso8601(),
        "firstSiteId" => if(rem(n, 7) == 0, do: archived, else: live)
      }
    end
  end

  defp counted(nil), do: []
  defp counted(period), do: period.agents

  # The period as the service shows it, its fee in cents with one decimal place.
  defp usage(nil), do: nil

  defp usage(period) do
    tenths = fee_tenths(length(period.agents))

    %{
      "periodStartsAt" => DateTime.to_iso8601(period.starts),
      "periodEndsAt" => DateTime.to_iso8601(period.ends),
      "activeAgents" => length(period.agents),
      "includedAgents" => @included_agents,
      "feeCents" => "#{div(tenths, 10)}.#{rem(tenths, 10)}",
      "capCents" => period.cap,
      "maxAgents" => max_agents(period.cap)
    }
  end

  defp fee_tenths(agents), do: @base_tenths + max(0, agents - @included_agents) * @agent_tenths

  defp max_agents(nil), do: nil
  defp max_agents(cap), do: @included_agents + div(cap * 10 - @base_tenths, @agent_tenths)

  # A cap is at least the least fee and never below the fee the period has reached.
  defp cap(params, _period) when not is_map_key(params, "capCents"),
    do: %{"capCents" => ["can't be blank; null means no cap"]}

  defp cap(%{"capCents" => nil}, _period), do: %{}

  defp cap(%{"capCents" => cap}, period) do
    cond do
      not is_integer(cap) -> %{"capCents" => ["is invalid"]}
      cap < @least_cap -> %{"capCents" => ["must be greater than or equal to #{@least_cap}"]}
      cap > @most_cap -> %{"capCents" => ["must be less than or equal to #{@most_cap}"]}
      period && fee_tenths(length(period.agents)) > cap * 10 -> below_fee()
      true -> %{}
    end
  end

  defp below_fee, do: %{"capCents" => ["is below the fee this period has already reached"]}

  defp page(params), do: Map.merge(limit(params["limit"]), cursor(params["after"]))

  defp limit(nil), do: %{}

  defp limit(limit) do
    case Integer.parse(limit) do
      {limit, ""} when limit in 1..@most_page -> %{}
      _other -> %{"limit" => ["must be from 1 to #{@most_page}"]}
    end
  end

  defp cursor(nil), do: %{}

  defp cursor(cursor),
    do: if(offset(cursor), do: %{}, else: %{"after" => ["is not a cursor this list gave"]})

  # The walk's cursor is how many agents the pages before gave.
  defp offset(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         {offset, ""} when offset > 0 <- Integer.parse(decoded) do
      offset
    else
      _not_a_cursor -> nil
    end
  end

  defp update_person(state, did, fun),
    do: %{state | people: Map.put(state.people, did, fun.(person(state, did)))}

  defp customer(state, did) do
    case person(state, did).customer do
      nil -> {:error, refusal(404, "customer_not_found", "this person has no customer yet")}
      customer -> {:ok, customer}
    end
  end

  defp no_customer(state, did) do
    case person(state, did).customer do
      nil -> :ok
      _customer -> {:error, refusal(409, "customer_exists", "this person already has a customer")}
    end
  end

  defp site(state, did, id) do
    with {:ok, _customer} <- customer(state, did) do
      case Enum.find(person(state, did).sites, &(&1["id"] == id and is_nil(&1["archivedAt"]))) do
        nil -> {:error, refusal(404, "site_not_found", "this person's customer has no such site")}
        site -> {:ok, site}
      end
    end
  end

  defp put_site(state, did, %{"id" => id} = site) do
    update_person(state, did, fn person ->
      %{person | sites: Enum.map(person.sites, &if(&1["id"] == id, do: site, else: &1))}
    end)
  end

  defp keys(state, did, site), do: Map.get(person(state, did).keys, site["id"], [])

  defp put_keys(state, did, site, keys),
    do: update_person(state, did, &%{&1 | keys: Map.put(&1.keys, site["id"], keys)})

  defp key(keys, key_id) do
    case Enum.find(keys, &(&1["id"] == key_id)) do
      nil -> {:error, refusal(404, "site_key_not_found", "this site has no such key")}
      key -> {:ok, key}
    end
  end

  defp room_for_key(keys) do
    if Enum.count(keys, &is_nil(&1["revokedAt"])) < @max_keys,
      do: :ok,
      else:
        {:error,
         refusal(
           409,
           "site_key_limit",
           "this site already has #{@max_keys} keys that are not revoked"
         )}
  end

  defp only(params, fields) when is_map(params) do
    case Map.keys(params) -- fields do
      [] -> {:ok, params}
      _other_fields -> request_invalid()
    end
  end

  defp only(_params, _fields), do: request_invalid()

  defp request_invalid,
    do:
      {:error,
       refusal(
         400,
         "control_request_invalid",
         "the request body has fields this step does not take"
       )}

  defp valid(fields) when fields == %{}, do: :ok

  defp valid(fields) do
    {:error,
     {422,
      %{
        "error" => %{
          "code" => "control_fields_invalid",
          "message" => "some fields are not valid",
          "hint" => "Correct each field named under fields, then send the request again.",
          "fields" => fields
        }
      }}}
  end

  # The fields a new site breaks, with the service's reasons.
  defp new_site(params, taken) do
    environment = params["environment"]

    environment_errors =
      cond do
        environment in ["sandbox", "production"] -> %{}
        is_nil(environment) -> %{"environment" => ["can't be blank"]}
        true -> %{"environment" => ["is invalid"]}
      end

    [
      name(params),
      audience(params["audience"], taken),
      environment_errors,
      origins(params, environment)
    ]
    |> Enum.reduce(&Map.merge/2)
  end

  defp name(%{"name" => name}) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> %{"name" => ["can't be blank"]}
      String.length(trimmed) > 100 -> %{"name" => ["should be at most 100 character(s)"]}
      true -> %{}
    end
  end

  defp name(%{"name" => name}) when not is_nil(name), do: %{"name" => ["is invalid"]}
  defp name(_params), do: %{"name" => ["can't be blank"]}

  defp audience(audience, _taken) when audience in [nil, ""],
    do: %{"audience" => ["can't be blank"]}

  defp audience(audience, _taken) when not is_binary(audience),
    do: %{"audience" => ["is invalid"]}

  defp audience(audience, taken) do
    cond do
      not Regex.match?(@audience, audience) ->
        %{
          "audience" => [
            "must be 1 to 64 lowercase letters, digits, - or _, starting with a letter or digit"
          ]
        }

      audience in @service_audiences or MapSet.member?(taken, audience) ->
        %{"audience" => ["has already been taken"]}

      true ->
        %{}
    end
  end

  defp origins(%{"origins" => origins}, environment) when is_list(origins) do
    cond do
      not Enum.all?(origins, &is_binary/1) -> %{"origins" => ["is invalid"]}
      origins == [] -> %{"origins" => ["should have at least 1 item(s)"]}
      length(origins) > 10 -> %{"origins" => ["should have at most 10 item(s)"]}
      Enum.uniq(origins) != origins -> %{"origins" => ["lists an origin twice"]}
      environment == "sandbox" -> rule(origins, @local, "http://localhost and a port")
      environment == "production" -> rule(origins, @https, "https:// and a lowercase host")
      true -> %{}
    end
  end

  defp origins(%{"origins" => origins}, _environment) when not is_nil(origins),
    do: %{"origins" => ["is invalid"]}

  defp origins(_params, _environment), do: %{"origins" => ["can't be blank"]}

  defp rule(origins, pattern, words) do
    if Enum.all?(origins, &Regex.match?(pattern, &1)),
      do: %{},
      else: %{"origins" => ["must each be #{words}, with nothing else"]}
  end

  defp refusal(status, code, message),
    do: {status, %{"error" => %{"code" => code, "message" => message, "hint" => nil}}}

  defp bearer(request) do
    case Req.Request.get_header(request, "authorization") do
      ["Bearer " <> bearer] -> bearer
      _none -> nil
    end
  end

  # A read's query, or a change's body.
  defp params(%Req.Request{method: :get, url: url}), do: URI.decode_query(url.query || "")
  defp params(%Req.Request{body: nil}), do: %{}
  defp params(%Req.Request{body: body}), do: body |> IO.iodata_to_binary() |> Jason.decode!()

  defp now, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()
end
