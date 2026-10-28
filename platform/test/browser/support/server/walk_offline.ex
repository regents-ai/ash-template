defmodule AshTemplate.WalkOffline do
  @moduledoc """
  The browser walk's server never leaves the machine. With `ASH_TEMPLATE_WALK` set
  (playwright.config.ts), every request the server makes through Req comes here
  first: one to this machine goes ahead, each Regent site's published tool list
  and IndexNow's receipt of the site's pages are answered here, and any other is written to the walk's list of outside
  requests and refused by raising, so a quick call fails the walk as surely as
  one that holds a connection open.
  """

  @this_machine ["127.0.0.1", "localhost", "::1"]

  # The addresses `AshTemplate.SiteTools` reads each site's tools from.
  @tool_lists [
    "https://regents.sh/capabilities.json",
    "https://patchbay.help/forum/capabilities",
    "https://techtree.sh/capabilities.json",
    "https://autolaunch.sh/capabilities",
    "https://keyfleet.ai/capabilities.json"
  ]

  def run(%Req.Request{url: %URI{host: host}} = request) when host in @this_machine,
    do: Req.Finch.run(request)

  def run(%Req.Request{method: :get, url: url} = request) do
    if URI.to_string(url) in @tool_lists,
      do: {request, Req.Response.json(%{"tools" => tools(url.host)})},
      else: refuse(:get, url)
  end

  def run(%Req.Request{method: :post, url: %URI{host: "api.indexnow.org"}} = request),
    do: {request, Req.Response.new(status: 202)}

  def run(%Req.Request{method: method, url: url}), do: refuse(method, url)

  # Three tools for each site: one for every page, one for its home page and one
  # for another page.
  defp tools(host) do
    for {verb, scope} <- [{"browse", "site"}, {"search", "/"}, {"post", "/forum"}] do
      %{
        "name" => "#{verb}_#{String.replace(host, ".", "_")}",
        "title" => "#{String.capitalize(verb)} #{host}",
        "description" => "The #{verb} tool #{host} offers agents.",
        "scope" => scope
      }
    end
  end

  defp refuse(method, url) do
    outside = "#{method |> to_string() |> String.upcase()} #{url.scheme}://#{url.host}#{url.path}"

    File.write!(
      Application.fetch_env!(:ash_template, :walk_outside_file),
      outside <> "\n",
      [:append]
    )

    raise "the browser walk refused a request outside this machine: #{outside}"
  end
end
