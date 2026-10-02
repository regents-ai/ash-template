defmodule AshTemplateWeb.RouteCatalog.RouteTarget do
  @moduledoc false
  @enforce_keys [:route_id, :label, :path]
  defstruct @enforce_keys
end
