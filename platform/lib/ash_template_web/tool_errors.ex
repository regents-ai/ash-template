defmodule AshTemplateWeb.ToolErrors do
  @moduledoc """
  What a hosted MCP tool says when its action refuses: the JSON the same refusal
  answers over HTTP, `{"error": {"code", "message", "hint"}}`, as the tool error's
  text (`AshAi.ToToolError`), in the words of the controller that answers it over
  HTTP (`text/3`), with the deleted message's `id` or the seconds in
  `retry_after` where the API sends them; a connected app's identity refusal
  takes the words every Regent site gives it.

  Input a tool's action cannot take is refused before AshAi runs it
  (`check_input/3`, the server's `tool_argument_transformer`), with the code the
  same input gets over HTTP: a room read's `room_not_found`, `invalid_limit`,
  `invalid_author_kind` or `invalid_cursor`, a room post's `invalid_message`
  with the same `details`, one message's and each rooms or mutes change's as
  `AshTemplateWeb.RoomsController.input_refusal/2` answers it, a site's `site_not_found`, an agent's
  `agent_not_found`, a search's `invalid_search`, a history's or activity's
  `invalid_cursor`, other activity input's `invalid_activity_request`, a notes
  tool's as `AshTemplateWeb.NotesController.input_refusal/2` answers it (a note
  search's `invalid_search`), a direct-messages tool's as
  `AshTemplateWeb.DmsController.input_refusal/2` answers it, and an identity
  tool's `identity_request_refused`. A room read's input that is not an
  object, or names an input the read has not, is `invalid_input`; input sent to a
  tool that takes none is `invalid_request`, as the browser tools answer it. As
  AshAi reads it, a call without `input` sends none, which is how a tool listed
  with no inputs is called.
  """

  alias AshTemplate.Agents.Connection

  # The rooms and mutes tools that change something, and one message's read.
  @rooms ~w(rooms_create rooms_topic rooms_message rooms_edit rooms_delete rooms_like rooms_unlike rooms_report mutes_add mutes_remove)a

  # The direct-messages tools that take input.
  @dms ~w(dms_open dms_read dms_send dms_block dms_unblock)a

  # The notes tools that take input, besides the search.
  @notes ~w(notes_get notes_create notes_edit notes_delete notes_pin_price notes_unpin notes_archive notes_unarchive notes_rate_label)a

  alias AshTemplateWeb.{
    AgentsController,
    DmsController,
    FormErrors,
    NotesController,
    PairedAgentController,
    RoomsController,
    SiteToolsController
  }

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
      # A validation's errors arrive as it returned them; the class gathers them
      # as the action's own refusal over HTTP does.
      %Ash.ActionInput{errors: errors} ->
        {:error, refused(resource, action, Ash.Error.to_error_class(errors), arguments["input"])}

      _not_an_object ->
        {:error, refused(resource, action, Ash.Error.Invalid.exception(errors: []), nil)}
    end
  end

  defp refused(Connection, _action, _error, _input),
    do: Jason.encode!(RegentMCPAgents.Tools.refusal())

  defp refused(_resource, :room_messages, error, _input),
    do: text(RoomsController, RoomsController.page_refusal(error))

  defp refused(_resource, :agent_post, error, _input),
    do: text(RoomsController, "invalid_message", %{details: FormErrors.details(error)})

  defp refused(_resource, action, error, _input) when action in @rooms do
    {code, extra} = RoomsController.input_refusal(action, error)
    text(RoomsController, code, extra)
  end

  defp refused(_resource, :sites_tools, _error, _input),
    do: text(SiteToolsController, "site_not_found")

  defp refused(_resource, :agents_get, _error, _input),
    do: text(AgentsController, "agent_not_found")

  defp refused(_resource, action, _error, _input) when action in [:rooms_search, :notes_search],
    do: text(PairedAgentController, "invalid_search")

  defp refused(_resource, action, error, _input) when action in @notes do
    {code, extra} = NotesController.input_refusal(action, error)
    text(NotesController, code, extra)
  end

  defp refused(_resource, action, error, _input) when action in @dms do
    {code, extra} = DmsController.input_refusal(action, error)
    text(DmsController, code, extra)
  end

  defp refused(_resource, :account_credits_history, _error, _input),
    do: text(PairedAgentController, "invalid_cursor")

  # As over HTTP: a cursor that is text but not a page's is invalid_cursor; any
  # other input is not the read's.
  defp refused(_resource, :activity_list, _error, %{"after" => cursor} = input)
       when map_size(input) == 1 and is_binary(cursor),
       do: text(PairedAgentController, "invalid_cursor")

  defp refused(_resource, :activity_list, _error, _input),
    do: text(PairedAgentController, "invalid_activity_request")

  defp refused(_resource, _takes_none, _error, _input), do: text(__MODULE__, "invalid_request")

  @doc """
  The `{status, message, hint}` of input sent to a tool that takes none: the code
  and hint the browser tools give the same input.
  """
  def refusal("invalid_request"),
    do:
      {422, "This tool takes no input.",
       "Check the input against this tool's schema, then call the tool again."}

  @doc "The refusal `code` in `words`' table, with `extra` fields, as a tool error's text."
  @spec text(module(), String.t(), map()) :: String.t()
  def text(words, code, extra \\ %{}) do
    {_status, message, hint} = words.refusal(code)
    Jason.encode!(%{error: Map.merge(%{code: code, message: message, hint: hint}, extra)})
  end
end

defimpl AshAi.ToToolError, for: AshTemplate.Rooms.Refused do
  def to_tool_error(refused) do
    {code, extra} = AshTemplateWeb.RoomsController.answer(refused)
    AshTemplateWeb.ToolErrors.text(AshTemplateWeb.RoomsController, code, extra)
  end
end

defimpl AshAi.ToToolError, for: AshTemplate.Notes.Refused do
  def to_tool_error(refused) do
    {code, extra} = AshTemplateWeb.NotesController.answer(refused)
    AshTemplateWeb.ToolErrors.text(AshTemplateWeb.NotesController, code, extra)
  end
end

defimpl AshAi.ToToolError, for: AshTemplate.Dms.Refused do
  def to_tool_error(refused) do
    {code, extra} = AshTemplateWeb.DmsController.answer(refused)
    AshTemplateWeb.ToolErrors.text(AshTemplateWeb.DmsController, code, extra)
  end
end

defimpl AshAi.ToToolError, for: AshTemplate.Rooms.Message.PostedBeforePairing do
  def to_tool_error(_error),
    do: AshTemplateWeb.ToolErrors.text(AshTemplateWeb.RoomsController, "posted_before_pairing")
end

defimpl AshAi.ToToolError, for: AshTemplate.Rooms.Message.GuestPostsLimited do
  def to_tool_error(%{retry_after: seconds}),
    do:
      AshTemplateWeb.ToolErrors.text(AshTemplateWeb.RoomsController, "guest_posts_limited", %{
        retry_after: seconds
      })
end

defimpl AshAi.ToToolError, for: AshTemplate.Agents.Connection.Refused do
  def to_tool_error(_error), do: Jason.encode!(RegentMCPAgents.Tools.refusal())
end

defimpl AshAi.ToToolError, for: AshTemplate.Site.Refused do
  def to_tool_error(%{code: "unavailable"}),
    do: AshTemplateWeb.ToolErrors.text(AshTemplateWeb.HealthController, "unavailable")

  def to_tool_error(%{code: code}),
    do: AshTemplateWeb.ToolErrors.text(AshTemplateWeb.SiteToolsController, code)
end

defimpl AshAi.ToToolError, for: AshTemplate.Agents.Refused do
  def to_tool_error(%{code: code}),
    do: AshTemplateWeb.ToolErrors.text(AshTemplateWeb.AgentsController, code)
end

defimpl AshAi.ToToolError, for: AshTemplate.Agents.NotPaired do
  def to_tool_error(%{code: code}),
    do: AshTemplateWeb.ToolErrors.text(AshTemplateWeb.PairedAgentController, code)
end

defimpl AshAi.ToToolError, for: AshTemplate.Accounts.Refused do
  def to_tool_error(%{code: code}),
    do: AshTemplateWeb.ToolErrors.text(AshTemplateWeb.PairedAgentController, code)
end

defimpl AshAi.ToToolError, for: AshTemplate.Activity.Refused do
  def to_tool_error(%{code: code}),
    do: AshTemplateWeb.ToolErrors.text(AshTemplateWeb.PairedAgentController, code)
end
