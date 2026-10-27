defmodule AshTemplate.IndexNowTest do
  # Invariants for telling search engines about public pages:
  # - each release's sitemap is queued once, however often the hourly job runs;
  # - the list carries this site's host, key and key file, and only this site's pages;
  # - an answer that would fail again stops for good; a busy one waits.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: AshTemplate.Repo, prefix: "ash_template_app"
  import Phoenix.ConnTest

  alias AshTemplate.IndexNow
  alias AshTemplateWeb.PublicDocuments

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    key = Application.get_env(:ash_template, :indexnow_key)
    Application.put_env(:ash_template, :indexnow_key, "test-indexnow-key")

    on_exit(fn ->
      if key,
        do: Application.put_env(:ash_template, :indexnow_key, key),
        else: Application.delete_env(:ash_template, :indexnow_key)

      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "each release's pages are queued once, however often the hourly job runs" do
    for _hour <- 1..3, do: assert(:ok = perform_job(IndexNow, %{}))

    assert [job] = all_enqueued(worker: IndexNow)
    assert job.args["urls"] == PublicDocuments.sitemap_urls()
    assert PublicDocuments.url("/") in job.args["urls"]
  end

  test "with no key set, the hourly job queues nothing" do
    Application.delete_env(:ash_template, :indexnow_key)

    assert :ok = perform_job(IndexNow, %{})
    assert [] = all_enqueued(worker: IndexNow)
    assert {:cancel, _no_key} = perform_job(IndexNow, %{"urls" => [PublicDocuments.url("/")]})
  end

  test "the list names this site, its key and the file that proves it" do
    urls = [PublicDocuments.url("/"), PublicDocuments.url("/docs")]
    test = self()

    Req.Test.stub(IndexNow, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:sent, conn.method, conn.host, Jason.decode!(body)})
      Plug.Conn.send_resp(conn, 202, "")
    end)

    assert :ok = perform_job(IndexNow, %{"urls" => urls})
    assert_receive {:sent, "POST", "api.indexnow.org", body}

    assert body == %{
             "host" => URI.parse(PublicDocuments.url("/")).host,
             "key" => "test-indexnow-key",
             "keyLocation" => PublicDocuments.url("/indexnow-key.txt"),
             "urlList" => urls
           }
  end

  test "a refused list stops for good, and a busy answer waits" do
    urls = [PublicDocuments.url("/")]

    for {status, outcome} <- [{200, :ok}, {422, :cancel}, {403, :cancel}, {429, :snooze}, {503, :error}] do
      Req.Test.stub(IndexNow, &Plug.Conn.send_resp(&1, status, ""))
      assert outcome(perform_job(IndexNow, %{"urls" => urls})) == outcome, "answer #{status}"
    end
  end

  test "the key file serves the key, and is not found without one" do
    conn = get_page("/indexnow-key.txt")
    assert conn.status == 200
    assert conn.resp_body == "test-indexnow-key"

    Application.delete_env(:ash_template, :indexnow_key)
    assert_error_sent 404, fn -> get_page("/indexnow-key.txt") end
  end

  defp get_page(path), do: dispatch(build_conn(), AshTemplateWeb.Endpoint, :get, path, nil)

  defp outcome(:ok), do: :ok
  defp outcome({outcome, _detail}), do: outcome
end
