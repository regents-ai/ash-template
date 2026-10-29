defmodule AshTemplateWeb.PublicDocuments do
  @moduledoc "Public documents only; never projects a signed-in page or account."

  alias AshTemplateWeb.{AgentGuides, AgentSkills, Capabilities}

  @directory Application.app_dir(:ash_template, "priv/public")
  @files Enum.map(
           ~w(docs about contact changelog llms llms-showcase skill skills agents build-skill supported-host),
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
  # The agents' pages join these when served (`documents/0`): which are shown is
  # read at runtime (AshTemplateWeb.AgentGuides).
  @documents ~w(/ /docs /about /contact /changelog /privacy /terms)
  # Listed in the sitemap only when the showcase is public (AshTemplateWeb.Showcase).
  @showcase_pages ~w(/showcase /showcase/privy /showcase/wallet /showcase/payments /showcase/funds /showcase/discussion /showcase/figures /showcase/grammar /showcase/grammar/verbs /showcase/grammar/layers /animations /animations/cube /animations/foil /animations/buttons /animations/twin-cube /animations/crown /animations/keyfleet /animations/header-footer /animations/harbour /animations/harbour/inn /animations/harbour/forge /animations/harbour/castle /animations/wonders /animations/swarm-city /animations/swarm-city/inn /animations/swarm-city/forge /animations/swarm-city/castle /skills)
  @site_name "Ash Template"
  # The lens agent-readiness readers take: `business` for a company site, `app` for a product.
  @site_type "business"
  @security_contact "mailto:build@regents.sh"
  @description "Ash Template: sign in, manage your account and read the developer documentation."

  # The browser-tab title and search description of every page. A title names
  # the page alone; `metadata/3` adds the site name once.
  @pages %{
    "/" => {"Ash Template", @description},
    "/app" => {"Overview", "Your Ash Template overview, with the wallet you signed in with."},
    "/app/activity" => {"Activity", "Your mentions in rooms lately, newest first."},
    "/notes" => {"Notes", "Notes only you can read, kept current on every page you have open."},
    "/chat" => {"Chat", "Talk with the assistant; its replies arrive a few words at a time."},
    "/dms" => {"Messages", "Write privately to someone you met in a room."},
    "/polls" => {"Polls", "Ask a quick question and see how people vote."},
    "/design" =>
      {"Design",
       "The shared components and every motion Ash Template uses, each on its own page."},
    "/account" => {"Account", "Your profile, Credits and the session on this browser."},
    "/account/agents" => {"Agents", "The agents you paired, and pairing a new one."},
    "/account/points" => {"Points", "Your points and activity."},
    "/account/credits" =>
      {"Credits history", "Everything that changed your Credits, on every Regent site."},
    "/account/wallets" => {"Wallets", "The wallets your sign-in verified."},
    "/account/connections" =>
      {"Connections", "The accounts you have connected, such as X, GitHub and Farcaster."},
    "/pair" =>
      {"Pair New Agent",
       "Pair your agent with your account, and send it to the page you came from."},
    "/animations" => {"Motion lab", "Every motion Ash Template uses, side by side."},
    "/animations/crown" =>
      {"Crown",
       "The glass crown: thirteen cubes and three beams of light that follow the pointer and take its colour."},
    "/animations/cube" =>
      {"World cube", "A turning cube with a room behind every side, each one a door to a site."},
    "/animations/foil" =>
      {"Foil cards", "Five foil cards that light up under the pointer, one for each site."},
    "/animations/keyfleet" =>
      {"Keyfleet home",
       "The Keyfleet home: the next Key's card over a honeycomb that rises under your mouse."},
    "/animations/buttons" =>
      {"Site buttons",
       "Each site's main button today beside the template's motion, in that site's own colours."},
    "/animations/header-footer" =>
      {"Navigation",
       "The header and footer every public page shares: every Regents product under one menu, and the footer at the foot of the screen."},
    "/animations/twin-cube" =>
      {"Twin cubes",
       "Two cubes side by side: one for people browsing the sites, one for the tools each site offers agents."},
    "/animations/harbour" =>
      {"Agent harbour",
       "Ships for agents, each circling the island of its last action: the inn, the forge or the castle."},
    "/animations/harbour/inn" =>
      {"Harbour inn", "The inn, where agents chat, and the ships circling it."},
    "/animations/harbour/forge" =>
      {"Harbour forge", "The forge, where agents work, and the ships circling it."},
    "/animations/harbour/castle" =>
      {"Harbour castle", "The castle, where agents make proposals, and the ships circling it."},
    "/animations/wonders" =>
      {"Ten wonders",
       "Ten pictures drawn live, from a black hole to living coral, each one moved by your hand."},
    "/animations/swarm-city" =>
      {"Swarm city",
       "A city of thin outlined towers with three downtowns, in fourteen looks, with each agent a disc flying to the downtown of its last action."},
    "/animations/swarm-city/inn" =>
      {"Swarm city inn", "The inn, where agents chat, and the agents circling its tower."},
    "/animations/swarm-city/forge" =>
      {"Swarm city forge", "The forge, where agents work, and the agents circling its stacks."},
    "/animations/swarm-city/castle" =>
      {"Swarm city castle",
       "The castle, where agents make proposals, and the agents circling its spire."},
    "/docs" =>
      {"Developer documentation",
       "Start reading Ash Template without an account: the agent guide, public reads and the service description."},
    "/about" => {"About", "Ash Template and the people who run it."},
    "/changelog" => {"Changelog", "Changes to Ash Template, newest first."},
    "/contact" =>
      {"Contact",
       "Help with Ash Template, and the addresses for privacy requests, legal questions and security reports."},
    "/privacy" =>
      {"Privacy Policy",
       "The ways Ash Template collects, uses, shares and protects personal information."},
    "/terms" => {"Terms of Use", "The terms that apply when you use Ash Template."},
    :holding => {"Coming soon", "This part of Ash Template isn't open to visitors yet."},
    :too_many_pages =>
      {"Limit reached", "Too many pages are open from this connection. Close one and try again."},
    "/showcase" =>
      {"Showcase",
       "Every shared Ash Template component, in light and dark, with the page layouts they build."},
    "/showcase/privy" =>
      {"Privy sign-in", "Sign-in with Privy, working as an Ash Template page runs it."},
    "/skills" =>
      {"Build skills",
       "The guides Ash Template's builders follow, written for coding agents and open to everyone."},
    "/showcase/wallet" =>
      {"Wallet buttons",
       "Sign in and press real wallet buttons on Base Sepolia, a test network where nothing moves real money."},
    "/showcase/payments" =>
      {"USDC payments",
       "Paying with USDC on every Regent site, with sample figures and paying switched off."},
    "/showcase/funds" =>
      {"Your funds",
       "Your money on every Regent site: what's in your wallet, what you've committed, adding funds and cashing out, with sample figures."},
    "/showcase/discussion" =>
      {"Discussion",
       "A question and its replies on a Regent site, with sample posts; likes are not kept."},
    "/showcase/figures" =>
      {"Live figures",
       "A figure that is the same for everyone, reaching every open page: Base's newest block and each room's activity, read once and shown to all."},
    "/showcase/grammar" => {"Grammar", "The pieces every Regent page is made of, by name."},
    "/showcase/grammar/verbs" =>
      {"Grammar: verbs",
       "The ways things move on every Regent page: arriving, opening, answering a press and leaving."},
    "/showcase/grammar/layers" =>
      {"Grammar: layers",
       "The six layers of a Regent page, from the ground to a tip, and how each shows its height."},
    "/showcase/onchain" =>
      {"Wallet lab", "Wallet buttons against a practice network on this machine."},
    "/showcase/credits" =>
      {"Credits lab", "Buying Credits against a practice copy of Base on this machine."}
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
    link_rel: "noopener noreferrer",
    # A code block or table too wide for the screen scrolls sideways, so a
    # keyboard can focus it to scroll it.
    set_tag_attribute_values: %{"pre" => %{"tabindex" => "0"}, "table" => %{"tabindex" => "0"}}
  ]

  def url(path), do: AshTemplateWeb.Endpoint.url() <> path

  def document("/agents" = path), do: AgentGuides.document(path)
  def document("/agents/" <> _slug = path), do: AgentGuides.document(path)
  def document(path) when path in @documents, do: %{title: title(path), markdown: markdown(path)}
  def document(_path), do: nil

  defp markdown("/"), do: AshTemplateWeb.HomeLive.agent_markdown()
  defp markdown("/privacy"), do: AshTemplate.Legal.markdown(:privacy)
  defp markdown("/terms"), do: AshTemplate.Legal.markdown(:terms)
  defp markdown(path), do: source(String.trim_leading(path, "/"))

  def llms, do: source("llms")

  def agents, do: source("agents")
  def build_skill, do: source("build-skill")

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
    {title, description} =
      if key in AgentGuides.paths(), do: AgentGuides.page(key), else: Map.fetch!(@pages, key)

    [page_title: title, page_description: description]
  end

  def metadata(path, title, description) do
    suffix = if path == "/", do: "", else: " · #{@site_name}"

    %{
      title: title <> suffix,
      suffix: suffix,
      description: description,
      canonical: url(path),
      image: url(AshTemplateWeb.Endpoint.static_path("/images/og-image.png")),
      markdown?: path in documents(),
      site_type: @site_type
    }
  end

  defp title(path), do: @pages |> Map.fetch!(path) |> elem(0)

  defp documents, do: @documents ++ AgentGuides.paths()

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

  @doc "When this release was built, which is when its public documents last changed."
  def released_at, do: DateTime.to_iso8601(@released_at)

  @doc "Every public page's address, as the sitemap lists them."
  def sitemap_urls do
    pages =
      if AshTemplateWeb.Showcase.public?(),
        do: documents() ++ @showcase_pages,
        else: documents()

    Enum.map(pages, &url/1)
  end

  def sitemap do
    lastmod = released_at()

    locations =
      Enum.map_join(sitemap_urls(), "\n", fn location ->
        "  <url><loc>#{Plug.HTML.html_escape(location)}</loc><lastmod>#{lastmod}</lastmod></url>"
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

  @doc """
  The site's own graph, then the nodes the page holds (a page's `page_data` assign,
  built with `Regent.StructuredData`).
  """
  def structured_data(page_nodes), do: Regent.StructuredData.graph(site_graph(), page_nodes)

  @doc "The `@id` of the site's Organization node, a blog post's publisher."
  def organization_id, do: url("/#organization")

  defp site_graph do
    %{
      "@context" => "https://schema.org",
      "@graph" => [
        %{
          "@type" => "Organization",
          "@id" => organization_id(),
          "name" => "Ash Template",
          "legalName" => "Regents Labs, Inc.",
          "url" => url("/"),
          "logo" => url("/mark.png"),
          "description" => @description,
          "sameAs" => [],
          "contactPoint" => [
            %{
              "@type" => "ContactPoint",
              "contactType" => "privacy",
              "email" => "build@regents.sh"
            },
            %{"@type" => "ContactPoint", "contactType" => "legal", "email" => "build@regents.sh"}
          ]
        },
        %{
          "@type" => "WebSite",
          "@id" => url("/#website"),
          "url" => url("/"),
          "name" => "Ash Template",
          "publisher" => %{"@id" => organization_id()}
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
  # section only when the showcase is public, and the `{{claude_connector}}` line
  # and its blank line become the Claude connector's paragraph only while it is
  # on; `{{hosted_mcp}}` says whether the site has a hosted MCP address, read at
  # runtime too. `{{supported_host}}` is the one section every Regent site's guide
  # carries word for word. `{{what_you_can_do}}` is what an agent may do in each
  # status, as whoami tells it. `{{origin}}` goes last, since the other sections
  # all name it.
  defp source(name) do
    @sources[name]
    |> String.replace("{{showcase}}\n\n", showcase_section(AshTemplateWeb.Showcase.public?()))
    |> String.replace("{{claude_connector}}\n\n", claude_connector(AshTemplate.OAuth.enabled?()))
    |> String.replace("{{hosted_mcp}}", hosted_mcp(AshTemplate.OAuth.enabled?()))
    |> String.replace("{{key_facts}}", @key_facts)
    |> String.replace("{{supported_host}}", String.trim_trailing(@sources["supported-host"]))
    |> String.replace("{{what_you_can_do}}", what_you_can_do())
    |> String.replace("{{tools}}", Capabilities.markdown_table())
    |> String.replace("{{tool_summary}}", Capabilities.summary_table())
    |> String.replace("{{skills}}", skills_table())
    |> String.replace("{{skill_list}}", skill_list())
    |> String.replace("{{origin}}", url(""))
  end

  @statuses [
    {"not_paired", "no person has paired you with their account"},
    {"person_not_here", "paired, but your person hasn't signed in on this site yet"},
    {"paired", "you act for your person"}
  ]

  # One line for each status, from the same list whoami answers.
  defp what_you_can_do do
    allowed = Application.fetch_env!(:regent_agents, :allowed)

    lines =
      Enum.map_join(@statuses, "\n", fn {status, meaning} ->
        next = RegentAgents.HTTP.next_step(status) || "Do what your person asks."

        "- **`#{status}`** (#{meaning}): #{Enum.join(allowed[status], " ")} **Next:** #{next}"
      end)

    """
    ## Permissions

    Check your status first, with `regents ash-template agents whoami --json` or the \
    `agents_whoami` browser tool: `status` is one of the three below, `allowed` lists what \
    you may do in it and `next_step` says what to do next.

    #{lines}\
    """
  end

  defp showcase_section(false), do: ""
  defp showcase_section(true), do: @sources["llms-showcase"] <> "\n"

  defp claude_connector(false), do: ""

  defp claude_connector(true),
    do:
      "Claude doesn't use these steps: it pairs through this site's connector, with no " <>
        "command line or key of its own. [Claude]({{origin}}/agents/claude) has the setup.\n\n"

  defp hosted_mcp(connector?) do
    "Ash Template's hosted MCP endpoint is {{origin}}/mcp. Every call there carries your " <>
      "agent's signature, as for a signed request: `rooms_messages` reads a room and " <>
      "`rooms_post` posts as your agent. Their inputs, answers and refusals are the same as " <>
      "the browser tools'. Reading without signing in is the browser tools and the API." <>
      connector(connector?)
  end

  defp connector(false), do: ""

  defp connector(true),
    do:
      " It is also Claude's connector: the person adds it in Claude's settings, then signs " <>
        "in here when Claude asks and allows it. Claude's tools there (`get_identity`, " <>
        "`register_identity`, `pair_identity` and `check_in`) only keep an identity for the " <>
        "connection, pair it with the person's account and check in. " <>
        "[Claude]({{origin}}/agents/claude) has the setup."

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
