defmodule AshTemplate.Agents.Connection.Listing do
  @moduledoc """
  Holds only while the hosted MCP server lists its tools (AshAi's
  `ash_ai_pre_check?`), for an app its person connected with the agent
  permission (`AshTemplate.OAuth.agent_scope/0`) whose identity is not their
  paired agent yet (`AshTemplate.Actors.ConnectedApp`). It is listed every tool
  that agent runs, so the list an app keeps from its first request is still
  right once it pairs. Running one takes the paired agent: until then the call
  is refused as `agent_not_paired` before anything is read
  (`AshTemplateWeb.ToolErrors.check_input/3`), and the policy beside this check
  refuses it as well.

  Like Ash's built-in actor checks, it knows the app by its `role` and the
  permission by its name, so the resources whose policies name it take no
  compile-time dependency on the rest of the site.
  """

  use Ash.Policy.SimpleCheck

  @agent_scope "ash-template.agent"

  @impl true
  def describe(_opts),
    do: "the hosted MCP server is listing tools for an app its person allowed to work as an agent"

  @impl true
  def match?(
        %{role: :connected_app, principal: %{scopes: scopes}},
        %{subject: %{context: %{private: %{ash_ai_pre_check?: true}}}},
        _opts
      ),
      do: @agent_scope in scopes

  def match?(_actor, _context, _opts), do: false
end
