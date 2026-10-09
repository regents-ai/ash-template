defmodule AshTemplateWeb.PublicDocuments do
  @moduledoc "Public documents only; never projects a signed-in page or account."

  alias AshTemplate.Rooms.Room
  alias AshTemplateWeb.AgentSkills

  @directory Application.app_dir(:ash_template, "priv/public")
  @files Enum.map(
           ~w(docs about contact changelog llms llms-showcase skill skills),
           &Path.join(@directory, &1 <> ".md")
         )
  for file <- @files, do: @external_resource(file)
  @sources Map.new(@files, &{Path.basename(&1, ".md"), File.read!(&1)})
  # The About page's Key facts, repeated in llms.txt so AI tools read the same facts.
  [_about, facts] = String.split(@sources["about"], "\n## Key facts\n")
  @key_facts "## Key facts\n" <> String.trim_trailing(hd(String.split(facts, "\n## ", parts: 2)))
  @openapi_path Path.join(@directory, "openapi.json")
  @external_resource @openapi_path
  @openapi @openapi_path |> File.read!() |> Jason.decode!()
  @documents ~w(/ /docs /about /contact /changelog /privacy /terms)
  # Listed in the sitemap only when the showcase is public (AshTemplateWeb.Showcase).
  @showcase_pages ~w(/showcase /showcase/privy /showcase/wallet /showcase/payments /showcase/funds /showcase/discussion /animations /skills)
  @site_name "Ash Template"
  # The lens agent-readiness readers take: `business` for a company site, `app` for a product.
  @site_type "business"
  @security_contact "mailto:build@regents.sh"
  @description "Ash Template: sign in with a wallet, manage your account and read the developer documentation."

  # The browser-tab title and search description of every page. A title names
  # the page alone; `metadata/3` adds the site name once.
  @pages %{
    "/" => {"Ash Template", @description},
    "/app" => {"Overview", "Your Ash Template overview, with the wallet you signed in with."},
    "/app/activity" =>
      {"Activity", "What has happened for you lately: mentions in rooms, newest first."},
    "/notes" => {"Notes", "Notes only you can read, kept current on every page you have open."},
    "/chat" => {"Chat", "Talk with the assistant; its replies arrive a few words at a time."},
    "/chat/original" =>
      {"Chat in Ash AI's look",
       "The same chat with the assistant, in the look Ash AI's chat generator gives it."},
    "/account" => {"Profile", "Who Ash Template knows you as, and the session on this browser."},
    "/account/points" => {"Points", "Your points and activity."},
    "/account/wallets" => {"Wallets", "The wallets your sign-in verified."},
    "/account/connections" =>
      {"Connections", "The accounts you have connected, such as X, GitHub and Farcaster."},
    "/animations" => {"Motion lab", "Every motion Ash Template uses, side by side."},
    "/docs" =>
      {"Developer documentation",
       "Start reading Ash Template without an account: the agent guide, public reads and the service description."},
    "/about" => {"About", "What Ash Template is and who runs it."},
    "/changelog" => {"What's new", "What changed in Ash Template lately, newest first."},
    "/contact" =>
      {"Contact",
       "How to reach Ash Template about privacy requests, legal questions and security reports."},
    "/privacy" =>
      {"Privacy Policy",
       "How Ash Template collects, uses, shares and protects personal information."},
    "/terms" => {"Terms of Use", "The terms that apply when you use Ash Template."},
    :holding => {"Not open yet", "This part of Ash Template isn't open to visitors yet."},
    "/showcase" =>
      {"Showcase",
       "Every shared Ash Template component, in light and dark, with the page layouts they build."},
    "/showcase/privy" =>
      {"Sign in with Privy",
       "Wallet sign-in with Privy, working as an Ash Template page runs it."},
    "/skills" =>
      {"Build skills",
       "The guides Ash Template's builders follow, written for coding agents and open to everyone."},
    "/showcase/wallet" =>
      {"Wallet buttons",
       "Sign in and press real wallet buttons on Base Sepolia, a test network where nothing moves real money."},
    "/showcase/payments" =>
      {"Pay with USDC",
       "How paying with USDC looks on every Regent site, with sample figures and paying switched off."},
    "/showcase/funds" =>
      {"Your funds",
       "How your money looks on every Regent site: what's in your wallet, what you've committed, adding funds and cashing out, with sample figures."},
    "/showcase/discussion" =>
      {"A discussion thread",
       "How a question and its replies read on a Regent site, with sample posts; likes are not kept."},
    "/showcase/onchain" =>
      {"Wallet lab", "Wallet buttons against a practice network on this machine."},
    "/showcase/credits" =>
      {"Credits lab", "Buying Credits against a practice copy of Base on this machine."}
  }
  @pages Map.merge(
           @pages,
           Map.new(Room.all(), &{"/rooms/#{&1.slug}", {"#{&1.name} room", &1.about}})
         )
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

  def document(path) when path in @documents, do: %{title: title(path), markdown: markdown(path)}
  def document(_path), do: nil

  defp markdown("/"), do: AshTemplateWeb.HomeLive.agent_markdown()
  defp markdown("/privacy"), do: AshTemplate.Legal.markdown(:privacy)
  defp markdown("/terms"), do: AshTemplate.Legal.markdown(:terms)
  defp markdown(path), do: source(String.trim_leading(path, "/"))

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

  @doc "The `page_title` and `page_description` assigns the root layout reads from every page."
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

    pages =
      if AshTemplateWeb.Showcase.public?(), do: @documents ++ @showcase_pages, else: @documents

    locations =
      Enum.map_join(pages, "\n", fn path ->
        "  <url><loc>#{Plug.HTML.html_escape(url(path))}</loc><lastmod>#{lastmod}</lastmod></url>"
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

  def recovery_links do
    [
      {"Home", "/"},
      {"Developer documentation", "/docs"},
      {"Agent guide", "/llms.txt"},
      {"OpenAPI", "/openapi.json"},
      {"Sitemap", "/sitemap.xml"}
    ]
  end

  # The `{{showcase}}` line and the blank line after it become the showcase
  # section only when the showcase is public. `{{origin}}` goes last, since the
  # other sections all name it.
  defp source(name) do
    @sources[name]
    |> String.replace("{{showcase}}\n\n", showcase_section(AshTemplateWeb.Showcase.public?()))
    |> String.replace("{{key_facts}}", @key_facts)
    |> String.replace("{{tools}}", AshTemplate.Capabilities.markdown_table())
    |> String.replace("{{skills}}", skills_table())
    |> String.replace("{{skill_list}}", skill_list())
    |> String.replace("{{origin}}", url(""))
  end

  defp showcase_section(false), do: ""
  defp showcase_section(true), do: @sources["llms-showcase"] <> "\n"

  defp skill_list,
    do: Enum.map_join(AgentSkills.skills(), "\n", &"- **#{skill_link(&1)}**: #{&1.description}")

  defp skills_table do
    rows =
      Enum.map_join(AgentSkills.skills(), "\n", fn skill ->
        "| #{skill_link(skill)} | #{skill.description} | " <>
          "[#{skill.name}.zip](#{skills_base()}/#{skill.name}.zip) |"
      end)

    "| Skill | Use it for | Download |\n| --- | --- | --- |\n" <> rows
  end

  defp skill_link(skill), do: "[#{skill.name}](#{skills_base()}/#{skill.name}/SKILL.md)"

  defp skills_base, do: "{{origin}}" <> AgentSkills.base()
end
