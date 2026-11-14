defmodule AshTemplate.WalkControl do
  @moduledoc """
  The browser walk's SIWA control API (`AshTemplate.SiwaControl`), answered in
  this server's memory for the run (`AshTemplate.WalkOffline`) under the
  service's own rules and in its own shapes: each person's company, its sites
  and each site's keys, at most five of them in use.

  The identity token of the Privy pair a page trades is taken as the person's
  DID, and the token it gets back names them. The access token
  `walk-unavailable` is answered as a service whose control API is off.
  """

  @base "/api/control/v1/"
  @max_keys 5
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
        case step(method, path, body(request), did, state) do
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

  defp step(:get, ["account"], _params, did, state),
    do: {:ok, 200, "account", %{"did" => did, "customer" => person(state, did).customer}, state}

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

  defp person(state, did),
    do: Map.get(state.people, did, %{customer: nil, sites: [], keys: %{}})

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

  defp body(%Req.Request{body: nil}), do: %{}
  defp body(%Req.Request{body: body}), do: body |> IO.iodata_to_binary() |> Jason.decode!()

  defp now, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()
end
