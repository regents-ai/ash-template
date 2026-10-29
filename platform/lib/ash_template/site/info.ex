defmodule AshTemplate.Site.Info do
  @moduledoc """
  The site's own reads, each one answer every surface gives: the HTTP API, the
  browser tools, regents-cli and the hosted MCP server. Anyone may read them
  over HTTP and in the browser; at `/mcp` a call carries an agent's signature
  or a connected app's token like any other (`AshTemplateWeb.Plugs.McpAgent`).
  Nothing is stored.
  """

  use Ash.Resource,
    domain: AshTemplate.Site,
    authorizers: [Ash.Policy.Authorizer]

  alias AshTemplate.Site.Refused
  alias AshTemplate.SiteTools
  alias AshTemplateWeb.PublicDocuments

  @sites Enum.map(SiteTools.sites(), &String.to_atom/1)

  actions do
    # `%{status: "ok"}` while the site's own database answers (`AshTemplate.Health`).
    action :health, :map do
      run fn _input, _context ->
        if AshTemplate.Health.database_ready?(),
          do: {:ok, %{status: "ok"}},
          else: {:error, Refused.exception(code: "unavailable")}
      end
    end

    action :about, :map do
      run fn _input, _context -> {:ok, document("/about")} end
    end

    action :docs, :map do
      run fn _input, _context -> {:ok, document("/docs")} end
    end

    # Another site's tools, from the last day's copy or read from it now.
    action :sites_tools, :map do
      argument :site, :atom,
        allow_nil?: false,
        constraints: [one_of: @sites],
        description: "Which site: regents, patchbay, techtree, autolaunch or keyfleet."

      run fn input, _context ->
        site = Atom.to_string(input.arguments.site)

        case SiteTools.tools(site) do
          {:ok, tools} -> {:ok, %{site: SiteTools.name(site), tools: tools}}
          {:error, :unreachable} -> {:error, Refused.exception(code: "site_unreachable")}
        end
      end
    end

    action :siwa_help, :map do
      run fn _input, _context ->
        {:ok, %{site: "siwa-server", connection: SiteTools.connection_help()}}
      end
    end
  end

  policies do
    # Anyone reads these, except an app connected to a person's account: its
    # token is for its identity tools alone (`AshTemplate.Agents.Connection`).
    policy always() do
      forbid_if actor_attribute_equals(:role, :connected_app)
      authorize_if always()
    end
  end

  # A public page as `{title, markdown}`.
  defp document(path) do
    %{title: title, markdown: markdown} = PublicDocuments.document(path)
    %{title: title, markdown: markdown}
  end
end
