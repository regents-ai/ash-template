defmodule AshTemplate.Actors.ConnectedApp do
  @moduledoc """
  An app a person connected to their account here, such as Claude, calling the
  hosted MCP server with the token its connection holds. `principal` is what
  `RegentOAuth.verify/3` answered for that token: the person's subject, the
  token, the client and the scopes the person approved. It may use only the
  connection's identity tools (`AshTemplate.Agents.Connection`).
  """
  @enforce_keys [:principal]
  defstruct [:principal, role: :connected_app]
end
