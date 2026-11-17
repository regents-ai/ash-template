defmodule AshTemplate.Actors.ConnectedApp do
  @moduledoc """
  An app a person connected to their account here, such as Claude, calling the
  hosted MCP server with the token its connection holds. `principal` is what
  `RegentOAuth.verify/3` answered for that token: the person's subject, the
  token, the client and the scopes the person approved. It runs only the
  connection's identity tools (`AshTemplate.Agents.Connection`); with the agent
  permission it is listed its paired agent's tools as well, each answering
  `agent_not_paired` (`AshTemplate.Agents.Connection.Listing`). Once that
  identity is paired with the person's account and the person allowed the
  site's agent permission, the app calls as its paired agent instead
  (`AshTemplate.Actors.Agent`, `connection`).
  """
  @enforce_keys [:principal]
  defstruct [:principal, role: :connected_app]
end
