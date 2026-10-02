defmodule AshTemplateWeb.Showcase.Catalog do
  @moduledoc "The showcase's explicit visual coverage and executable API inventory."

  @components [
    {Regent.Primitives, [:button, :field, :status, :notice, :empty_state, :disclosure]},
    {Regent.Structure,
     [:frame, :row, :section_bar, :panel, :technical_figure, :capability_card, :ratio_card]},
    {Regent.ThemeToggle, [:button]},
    {AshTemplateWeb.Components.Shell, [:shell, :account_control, :theme_toggle]},
    {AshTemplateWeb.Components.VerifiedConnections, [:verified_connections]},
    {AshTemplateWeb.Layouts, [:app, :root]}
  ]

  def snapshot do
    %{
      components: components(),
      domains: domains(),
      utilities: utilities(),
      ash_phoenix_installed: Code.ensure_loaded?(AshPhoenix.Form)
    }
  end

  defp components do
    for {module, names} <- @components, name <- names do
      %{attrs: attrs, slots: slots} =
        Map.get(module.__components__(), name, %{attrs: [], slots: []})

      %{
        module: inspect(module),
        function: Atom.to_string(name),
        attributes: Enum.map(attrs, &Atom.to_string(&1.name)),
        slots: Enum.map(slots, &Atom.to_string(&1.name))
      }
    end
  end

  defp domains do
    for domain <- Application.fetch_env!(:ash_template, :ash_domains) do
      %{
        name: inspect(domain),
        resources: Enum.map(Ash.Domain.Info.resources(domain), &resource/1)
      }
    end
  end

  defp resource(resource) do
    %{
      name: inspect(resource),
      attributes:
        Enum.map(Ash.Resource.Info.attributes(resource), &%{name: &1.name, public: &1.public?}),
      actions: Enum.map(Ash.Resource.Info.actions(resource), &%{name: &1.name, type: &1.type})
    }
  end

  defp utilities do
    shared =
      for module <- Application.spec(:regent_privy, :modules),
          do: {module, "Shared by every site"}

    product = [{AshTemplate.DatabaseConfig, "This site only"}]

    for {module, owner} <-
          Enum.sort_by(shared ++ product, fn {module, _owner} -> inspect(module) end),
        functions = exported_functions(module),
        functions != [],
        do: %{name: inspect(module), owner: owner, functions: functions}
  end

  defp exported_functions(module) do
    for {name, arity} <- module.__info__(:functions),
        not String.starts_with?(Atom.to_string(name), "__"),
        do: "#{name}/#{arity}"
  end
end

defmodule AshTemplateWeb.Showcase.CatalogController do
  use AshTemplateWeb, :controller

  # The path is the fixed priv stylesheet; no request value reaches send_file.
  # sobelow_skip ["Traversal.SendFile"]
  def style(conn, _params),
    do:
      conn
      |> put_resp_content_type("text/css")
      |> send_file(200, Application.app_dir(:ash_template, "priv/showcase.css"))

  def show(conn, _params), do: json(conn, AshTemplateWeb.Showcase.Catalog.snapshot())
end
