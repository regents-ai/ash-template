defmodule AshTemplateWeb.ToolErrors do
  @moduledoc """
  What a hosted MCP tool says when its action refuses: the JSON the same refusal
  answers over HTTP, `{"error": {"code", "message", "hint"}}`, as the tool error's
  text (`AshAi.ToToolError`). A room's refusals take the rooms API's words
  (`AshTemplateWeb.RoomsController.refusal/1`), with the deleted message's `id`
  or the seconds in `retry_after` where the API sends them; a connected app's
  identity refusal takes the words every Regent site gives it.

  Input a tool's action cannot take is refused before AshAi runs it
  (`check_input/3`, the server's `tool_argument_transformer`), with the code the
  same input gets over HTTP: a room read's `room_not_found`, `invalid_limit`,
  `invalid_author_kind` or `invalid_cursor`, a room post's `invalid_message`
  with the same `details`, and an identity tool's `identity_request_refused`.
  A room read's input that is not an object, or names an input the read has
  not, is `invalid_input`. As AshAi reads it, a call without `input` sends none,
  which is how a tool listed with no inputs is called.
  """

  alias AshTemplateWeb.{FormErrors, RoomsController}

  @doc """
  Casts a hosted tool's `input` as its action takes it. Input it takes goes on to
  AshAi unchanged; any other is refused as `{:error, text}` with the HTTP code.
  """
  @spec check_input(AshAi.Tool.t(), term(), map()) :: {:ok, term()} | {:error, String.t()}
  def check_input(%AshAi.Tool{resource: resource, action: %{name: action}}, arguments, _context) do
    with %{} <- arguments,
         %{} = input <- arguments["input"] || %{},
         %{valid?: true} <- Ash.ActionInput.for_action(resource, action, input) do
      {:ok, arguments}
    else
      %Ash.ActionInput{errors: errors} ->
        {:error, refused(action, Ash.Error.Invalid.exception(errors: errors))}

      _not_an_object ->
        {:error, refused(action, Ash.Error.Invalid.exception(errors: []))}
    end
  end

  defp refused(:room_messages, error), do: room(RoomsController.page_refusal(error))

  defp refused(:agent_post, error),
    do: room("invalid_message", %{details: FormErrors.details(error)})

  defp refused(_identity, _error), do: Jason.encode!(RegentMCPAgents.Tools.refusal())

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
