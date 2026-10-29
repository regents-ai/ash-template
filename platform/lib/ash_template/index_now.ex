defmodule AshTemplate.IndexNow do
  @moduledoc """
  Tells the search engines that read IndexNow (Bing, which ChatGPT search reads,
  Yandex and others) which public pages are new or changed, so they read them
  again soon instead of on their own schedule.

  The key is the server setting `ASH_TEMPLATE_INDEXNOW_KEY`; with none set, nothing
  is sent and `/indexnow-key.txt` is not found. The key is public by design:
  that file serves it, which proves the list came from this site.

  Each release's pages are sent once: an hourly job queues one submission of the
  sitemap, unique to the running release. A site that adds or changes a
  public page queues `submit/1` with its address in the same transaction.
  """
  use Oban.Worker, queue: :outside_calls, max_attempts: 5

  alias AshTemplateWeb.PublicDocuments

  @endpoint "https://api.indexnow.org/indexnow"
  @key_path "/indexnow-key.txt"

  @doc "The site's IndexNow key, or nil when none is set."
  @spec key() :: String.t() | nil
  def key, do: Application.get_env(:ash_template, :indexnow_key)

  # A list waits in these states; once its sending has started, it is no longer
  # the same job as a list queued after a later change.
  @waiting [:available, :scheduled, :retryable]

  @doc """
  A job that sends `urls`, this site's own addresses (at most 10,000). The same
  list queued again while one is still waiting to be sent is that one job.
  """
  @spec submit([String.t()]) :: Oban.Job.changeset()
  def submit(urls) do
    new(%{"urls" => urls}, unique: [keys: [:urls], period: :infinity, states: @waiting])
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"urls" => urls}}), do: deliver(key(), urls)

  # The hourly job: queue the sitemap once for each release, which is when the
  # public pages change.
  def perform(%Oban.Job{args: %{}}) do
    if key() do
      %{"urls" => PublicDocuments.sitemap_urls(), "released" => PublicDocuments.released_at()}
      |> new(unique: [period: :infinity, keys: [:released], states: :all])
      |> Oban.insert!()
    end

    :ok
  end

  defp deliver(nil, _urls), do: {:cancel, "no IndexNow key is set"}

  defp deliver(key, urls) do
    body = %{
      host: URI.parse(PublicDocuments.url("/")).host,
      key: key,
      keyLocation: PublicDocuments.url(@key_path),
      urlList: urls
    }

    request =
      Req.new(url: @endpoint, retry: false, redirect: false, receive_timeout: 15_000)
      |> Req.merge(Application.get_env(:ash_template, :indexnow_req, []))

    case Req.post(request, json: body) do
      {:ok, %{status: status}} when status in [200, 202] ->
        :ok

      {:ok, %{status: 429}} ->
        {:snooze, 600}

      # A list the engines refuse (a bad request, a key they could not read, or an
      # address that is not this site's) fails again on every attempt.
      {:ok, %{status: status}} when status in [400, 403, 422] ->
        {:cancel, "IndexNow answered #{status}"}

      {:ok, %{status: status}} ->
        {:error, "IndexNow answered #{status}"}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end
end
