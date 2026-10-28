defmodule AshTemplateWeb.ToolErrors do
  @moduledoc """
  What a hosted MCP tool says when its action refuses: the JSON the same refusal
  answers over HTTP, `{"error": {"code", "message", "hint"}}`, as the tool error's
  text (`AshAi.ToToolError`). A room's refusals take the rooms API's words
  (`AshTemplateWeb.RoomsController.refusal/1`), with the deleted message's `id`
  or the seconds in `retry_after` where the API sends them; a connected app's
  identity refusal takes the words every Regent site gives it.
  """

  alias AshTemplateWeb.RoomsController

  @doc "The rooms API's refusal `code`, with `extra` fields, as a tool error's text."
  @spec room(String.t(), map()) :: String.t()
  def room(code, extra \\ %{}) do
    {_status, message, hint} = RoomsController.refusal(code)
    Jason.encode!(%{error: Map.merge(%{code: code, message: message, hint: hint}, extra)})
  end
end

defimpl AshAi.ToToolError, for: AshTemplate.Rooms.Refused do
  def to_tool_error(%{code: "message_removed", id: id}),
    do: AshTemplateWeb.ToolErrors.room("message_removed", %{id: id})

  def to_tool_error(%{code: code}), do: AshTemplateWeb.ToolErrors.room(code)
end

defimpl AshAi.ToToolError, for: AshTemplate.Rooms.Message.PostedBeforePairing do
  def to_tool_error(_error), do: AshTemplateWeb.ToolErrors.room("posted_before_pairing")
end

defimpl AshAi.ToToolError, for: AshTemplate.Rooms.Message.GuestPostsLimited do
  def to_tool_error(%{retry_after: seconds}),
    do: AshTemplateWeb.ToolErrors.room("guest_posts_limited", %{retry_after: seconds})
end

defimpl AshAi.ToToolError, for: AshTemplate.Agents.Connection.Refused do
  def to_tool_error(_error), do: Jason.encode!(RegentMCPAgents.Tools.refusal())
end
