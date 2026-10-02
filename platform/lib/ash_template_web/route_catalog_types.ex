defmodule AshTemplateWeb.RouteCatalog.RouteTarget do
  @moduledoc false
  @enforce_keys [:route_id, :label, :path]
  defstruct @enforce_keys
end

defmodule AshTemplateWeb.RouteCatalog.SidebarHeading do
  @moduledoc false
  @enforce_keys [:label]
  defstruct @enforce_keys
end
