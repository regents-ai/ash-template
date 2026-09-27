defmodule AshTemplateWeb.PublicDocuments do
  @moduledoc "Public documents only; never projects a signed-in page or account."

  @directory Application.app_dir(:ash_template, "priv/public")
  @files Enum.map(~w(docs about contact llms), &Path.join(@directory, &1 <> ".md"))
  for file <- @files, do: @external_resource(file)
  @sources Map.new(@files, &{Path.basename(&1, ".md"), File.read!(&1)})
  @openapi_path Path.join(@directory, "openapi.json")
  @external_resource @openapi_path
  @openapi @openapi_path |> File.read!() |> Jason.decode!()
  @documents ~w(/ /docs /about /contact /privacy /terms)
  @site_name "Ash Template"
  @description "Ash Template: sign in with a wallet, manage your account and read the developer documentation."

  # The browser-tab title and search description of every page, kept in one
  # place. A title names the page alone; `metadata/3` adds the site name once.
  @pages %{
    "/" => {"Ash Template", @description},
    "/app" => {"Overview", "Your Ash Template overview, with the wallet you signed in with."},
    "/account" =>
      {"Account", "The wallet you signed in with and the accounts you have connected."},
    "/animations" => {"Motion lab", "Every motion Ash Template uses, side by side."},
    "/docs" =>
      {"Developer documentation",
       "Start reading Ash Template without an account: the agent guide, public reads and the service description."},
    "/about" => {"About", "What Ash Template is and who runs it."},
    "/contact" =>
      {"Contact",
       "How to reach Ash Template about privacy requests, legal questions and security reports."},
    "/privacy" =>
      {"Privacy Policy",
       "How Ash Template collects, uses, shares and protects personal information."},
    "/terms" => {"Terms of Use", "The terms that apply when you use Ash Template."},
    :holding => {"Not open yet", "This part of Ash Template isn't open to visitors yet."},
    "/showcase" => {"Showcase", "The Ash Template component showcase."},
    "/showcase/privy" => {"Privy integration", "The Ash Template sign-in reference page."},
    "/showcase/onchain" => {"Wallet buttons", "The Ash Template wallet-button workshop."}
  }
  @sanitize [
    tags: ~w(h1 h2 h3 p ul ol li strong em a code pre br blockquote),
    tag_attributes: %{"a" => ["href"]},
    generic_attributes: [],
    url_schemes: ~w(http https mailto),
    url_relative: :deny,
    link_rel: "noopener noreferrer"
  ]

  def url(path), do: AshTemplateWeb.Endpoint.url() <> path

  def document("/"),
    do: %{title: "Ash Template", markdown: AshTemplateWeb.HomeLive.agent_markdown()}

  def document("/privacy"),
    do: %{title: "Privacy Policy", markdown: AshTemplate.Legal.markdown(:privacy)}

  def document("/terms"),
    do: %{title: "Terms of Use", markdown: AshTemplate.Legal.markdown(:terms)}

  def document(path) when path in ~w(/docs /about /contact),
    do: %{title: title(path), markdown: source(String.trim_leading(path, "/"))}

  def document(_path), do: nil

  def llms, do: source("llms")

  # The HTML is MDEx-sanitized from the committed public markdown.
  # sobelow_skip ["XSS.Raw"]
  def html(markdown) do
    markdown |> MDEx.to_html!(sanitize: @sanitize) |> Phoenix.HTML.raw()
  end

  @doc """
  The `page_title` and `page_description` assigns the root layout reads. Every
  page that renders in the root layout assigns them from here.
  """
  def page(key) do
    {title, description} = Map.fetch!(@pages, key)
    [page_title: title, page_description: description]
  end

  def metadata(path, title, description) do
    suffix = if path == "/", do: "", else: " · #{@site_name}"

    %{
      title: title <> suffix,
      suffix: suffix,
      description: description,
      canonical: url(path),
      image: url("/mark.png"),
      markdown?: path in @documents
    }
  end

  defp title(path), do: @pages |> Map.fetch!(path) |> elem(0)

  def openapi do
    @openapi
    |> Map.put("servers", [%{"url" => url("")}])
    |> Map.put("externalDocs", %{
      "url" => url("/docs"),
      "description" => "Developer documentation"
    })
    |> put_in(["info", "contact", "url"], url("/contact"))
    |> put_in(["info", "termsOfService"], url("/terms"))
  end

  def sitemap do
    locations =
      Enum.map_join(@documents, "\n", fn path ->
        location = url(path) |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        "  <url><loc>#{location}</loc></url>"
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{locations}
    </urlset>
    """
  end

  def structured_data do
    %{
      "@context" => "https://schema.org",
      "@graph" => [
        %{
          "@type" => "Organization",
          "@id" => url("/#organization"),
          "name" => "Ash Template",
          "legalName" => "Ash Template",
          "url" => url("/"),
          "logo" => url("/mark.png"),
          "description" => @description,
          "sameAs" => [],
          "contactPoint" => [
            %{
              "@type" => "ContactPoint",
              "contactType" => "privacy",
              "email" => "privacy@example.com"
            },
            %{"@type" => "ContactPoint", "contactType" => "legal", "email" => "legal@example.com"}
          ]
        },
        %{
          "@type" => "WebSite",
          "@id" => url("/#website"),
          "url" => url("/"),
          "name" => "Ash Template",
          "publisher" => %{"@id" => url("/#organization")}
        }
      ]
    }
  end

  defp source(name), do: String.replace(@sources[name], "{{origin}}", url(""))

  def recovery_links do
    [
      {"Home", "/"},
      {"Developer documentation", "/docs"},
      {"Agent guide", "/llms.txt"},
      {"OpenAPI", "/openapi.json"},
      {"Sitemap", "/sitemap.xml"}
    ]
  end
end
