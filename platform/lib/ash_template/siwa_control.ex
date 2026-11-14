defmodule AshTemplate.SiwaControl do
  @moduledoc """
  The sign-in service's control API (`/api/control/v1` at the address in
  `config :regent_agents, :siwa`), which keeps a person's SIWA company, its
  sites and each site's server keys. This site keeps no copy of them: the SIWA
  pages (`AshTemplateWeb.SiwaLive`) read them here every time.

  The person is proven to the service by trading their Privy sign-in for a
  control token (`session/1`), which lasts fifteen minutes and is kept only on
  this machine (`AshTemplate.SiwaControl.Tokens`). Every other call takes that
  token.

  Each call answers `{:ok, data}`, the service's own data with its own keys;
  `{:error, %Refusal{}}`, the service's refusal with its status, code, message,
  hint and the reasons for each field it refused; or `{:error, :unavailable}`
  when the service did not answer or answered something else. No call is sent
  twice, so a change the service may already have made is never repeated, and
  nothing a call carries reaches a log or an error.
  """

  defmodule Refusal do
    @moduledoc "A refusal from the control API, as the service gave it."
    @type t :: %__MODULE__{
            status: pos_integer(),
            code: String.t(),
            message: String.t(),
            hint: String.t() | nil,
            fields: %{optional(String.t()) => [String.t()]}
          }
    defstruct [:status, :code, :message, :hint, fields: %{}]
  end

  defmodule Secret do
    @moduledoc """
    A new site key, as the service gives it the one time it does. It never
    prints, so no log, crash report or error can show it.
    """
    @derive {Inspect, only: []}
    @enforce_keys [:value]
    defstruct [:value]
  end

  @type result :: {:ok, term()} | {:error, Refusal.t() | :unavailable}

  @doc "The sign-in service's address, such as `https://siwa.regents.sh`."
  @spec url() :: String.t()
  def url, do: Application.fetch_env!(:regent_agents, :siwa)[:url]

  @doc ~s(Trades the person's Privy pair for `%{"token", "expiresAt", "did"}`.)
  @spec session(%{access: String.t(), identity: String.t()}) :: result()
  def session(%{access: access, identity: identity}),
    do: call(access, method: :post, url: "/session", headers: [{"privy-id-token", identity}])

  @doc ~s(The person the token names and their company, `%{"did", "customer"}`; no company is nil.)
  @spec account(String.t()) :: result()
  def account(token), do: call(token, method: :get, url: "/account")

  @doc "Makes the person's company from `%{\"name\" => _}`."
  @spec create_customer(String.t(), map()) :: result()
  def create_customer(token, params),
    do: call(token, method: :post, url: "/customer", json: params)

  @doc "Renames the person's company with `%{\"name\" => _}`."
  @spec update_customer(String.t(), map()) :: result()
  def update_customer(token, params),
    do: call(token, method: :patch, url: "/customer", json: params)

  @doc "The company's sites that are not archived, oldest first, as `%{\"sites\" => _}`."
  @spec list_sites(String.t()) :: result()
  def list_sites(token), do: call(token, method: :get, url: "/sites")

  @doc "One of the company's sites."
  @spec get_site(String.t(), String.t()) :: result()
  def get_site(token, id), do: call(token, method: :get, url: "/sites/:id", path_params: [id: id])

  @doc "Adds a site from `name`, `audience`, `environment` and `origins`."
  @spec create_site(String.t(), map()) :: result()
  def create_site(token, params), do: call(token, method: :post, url: "/sites", json: params)

  @doc "Renames a site or changes its origins, from `name` and `origins`."
  @spec update_site(String.t(), String.t(), map()) :: result()
  def update_site(token, id, params),
    do: call(token, method: :patch, url: "/sites/:id", path_params: [id: id], json: params)

  @doc "Archives a site. Its audience stays taken."
  @spec archive_site(String.t(), String.t()) :: result()
  def archive_site(token, id),
    do: call(token, method: :delete, url: "/sites/:id", path_params: [id: id])

  @doc "A site's keys, revoked ones included, newest first, as `%{\"keys\" => _}`."
  @spec list_site_keys(String.t(), String.t()) :: result()
  def list_site_keys(token, id),
    do: call(token, method: :get, url: "/sites/:id/keys", path_params: [id: id])

  @doc """
  Makes a server key for a site. The answer's `key`, the only time the key is
  given, comes as a `Secret`.
  """
  @spec create_site_key(String.t(), String.t()) :: result()
  def create_site_key(token, id) do
    case call(token, method: :post, url: "/sites/:id/keys", path_params: [id: id]) do
      {:ok, %{"key" => key} = made} when is_binary(key) ->
        {:ok, %{made | "key" => %Secret{value: key}}}

      {:ok, _no_key} ->
        {:error, :unavailable}

      refused_or_unavailable ->
        refused_or_unavailable
    end
  end

  @doc "Revokes one of a site's keys."
  @spec revoke_site_key(String.t(), String.t(), String.t()) :: result()
  def revoke_site_key(token, id, key_id),
    do:
      call(token,
        method: :delete,
        url: "/sites/:id/keys/:key_id",
        path_params: [id: id, key_id: key_id]
      )

  # The body is read here rather than by Req, so a body that is not JSON is an
  # answer like any other and never an exception carrying the request.
  defp call(bearer, options) do
    [
      base_url: url() <> "/api/control/v1",
      auth: {:bearer, bearer},
      retry: false,
      redirect: false,
      decode_body: false,
      connect_options: [timeout: 3_000],
      receive_timeout: 10_000
    ]
    |> Req.new()
    |> Req.merge(Application.get_env(:ash_template, :siwa_control_req, []))
    |> Req.request(options)
    |> answer()
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}) when is_binary(body) do
    case {status, Jason.decode(body)} do
      {status, {:ok, %{"code" => code, "data" => data}}}
      when status in 200..299 and is_binary(code) ->
        {:ok, data}

      {status, {:ok, %{"error" => %{"code" => code, "message" => message} = error}}}
      when status in 400..599 and is_binary(code) and is_binary(message) ->
        {:error,
         %Refusal{
           status: status,
           code: code,
           message: message,
           hint: error["hint"],
           fields: fields(error["fields"])
         }}

      _other ->
        {:error, :unavailable}
    end
  end

  defp answer(_no_answer), do: {:error, :unavailable}

  defp fields(%{} = fields) do
    for {field, reasons} when is_list(reasons) <- fields,
        reasons = Enum.filter(reasons, &is_binary/1),
        reasons != [],
        into: %{},
        do: {field, reasons}
  end

  defp fields(_none), do: %{}
end
