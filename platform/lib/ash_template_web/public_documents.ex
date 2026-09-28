defmodule AshTemplateWeb.PublicDocuments do
  @moduledoc "Public documents only; never projects a signed-in page or account."

  @directory Application.app_dir(:ash_template, "priv/public")
  @files Enum.map(~w(docs about contact llms skill skills), &Path.join(@directory, &1 <> ".md"))
  for file <- @files, do: @external_resource(file)
  @sources Map.new(@files, &{Path.basename(&1, ".md"), File.read!(&1)})
  @openapi_path Path.join(@directory, "openapi.json")
  @external_resource @openapi_path
  @openapi @openapi_path |> File.read!() |> Jason.decode!()
  @documents ~w(/ /docs /about /contact /privacy /terms)
  # Site settings: the name; the type agent-readiness readers take as their lens,
  # `business` for a company site or `app` for a product people use; and where
  # security reports go, as published in security.txt.
  @site_name "Ash Template"
  @site_type "business"
  @security_contact "mailto:security@example.com"
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
    "/skills" =>
      {"Build skills",
       "The guides Ash Template's builders follow, written for coding agents and open to everyone."},
    "/showcase/wallet" =>
      {"Wallet buttons",
       "Sign in and press real wallet buttons on Base Sepolia, a test network where nothing moves real money."},
    "/showcase/onchain" =>
      {"Wallet lab", "Wallet buttons against a practice network on this machine."}
  }
  # The public documents change only with a release, so the release time is when
  # each last changed.
  @released_at DateTime.utc_now() |> DateTime.truncate(:second)
  @sanitize [
    tags: ~w(h1 h2 h3 p ul ol li strong em a code pre br blockquote table thead tbody tr th td),
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

  @doc "The agent guide served at `/skill.md`."
  def skill_guide, do: source("skill")

  @doc "The build skills page for people at `/skills`."
  def skills_page, do: %{title: title("/skills"), markdown: source("skills")}

  # The HTML is MDEx-sanitized from the committed public markdown.
  # sobelow_skip ["XSS.Raw"]
  def html(markdown) do
    markdown |> MDEx.to_html!(extension: [table: true], sanitize: @sanitize) |> Phoenix.HTML.raw()
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
      markdown?: path in @documents,
      site_type: @site_type
    }
  end

  defp title(path), do: @pages |> Map.fetch!(path) |> elem(0)

  def openapi do
    @openapi
    |> Map.put("servers", [%{"url" => url("")}])
    |> Map.put("externalDocs", %{
      "url" => url("/docs"),
      "description" =>
        "Developer documentation: errors, rate limits, and the versioning and deprecation policy"
    })
    |> put_in(["info", "contact", "url"], url("/contact"))
    |> put_in(["info", "termsOfService"], url("/terms"))
  end

  def sitemap do
    lastmod = DateTime.to_iso8601(@released_at)

    locations =
      Enum.map_join(@documents, "\n", fn path ->
        location = url(path) |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        "  <url><loc>#{location}</loc><lastmod>#{lastmod}</lastmod></url>"
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{locations}
    </urlset>
    """
  end

  @doc "The RFC 9116 security contact file; it expires a year after the release."
  def security_txt do
    """
    Contact: #{@security_contact}
    Expires: #{@released_at |> DateTime.shift(year: 1) |> DateTime.to_iso8601()}
    Preferred-Languages: en
    Canonical: #{url("/.well-known/security.txt")}
    Policy: #{url("/contact")}
    """
  end

  @doc "The RFC 9727 API catalog: a linkset naming the API, its description and its documentation."
  def api_catalog do
    %{
      "linkset" => [
        %{
          "anchor" => url("/api/v1"),
          "service-desc" => [%{"href" => url("/openapi.json"), "type" => "application/json"}],
          "service-doc" => [%{"href" => url("/docs"), "type" => "text/html"}]
        }
      ]
    }
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

  # `{{tools}}` is the browser tools table, from the one tool manifest, and
  # `{{skills}}` the build skills table. `{{origin}}` goes last, since both
  # tables name it.
  defp source(name) do
    @sources[name]
    |> String.replace("{{tools}}", AshTemplate.Capabilities.markdown_table())
    |> String.replace("{{skills}}", skills_table())
    |> String.replace("{{origin}}", url(""))
  end

  defp skills_table do
    base = "{{origin}}" <> AshTemplateWeb.AgentSkills.base()

    rows =
      Enum.map_join(AshTemplateWeb.AgentSkills.skills(), "\n", fn skill ->
        "| [#{skill.name}](#{base}/#{skill.name}/SKILL.md) | #{skill.description} | " <>
          "[#{skill.name}.zip](#{base}/#{skill.name}.zip) |"
      end)

    "| Skill | Use it for | Download |\n| --- | --- | --- |\n" <> rows
  end

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
