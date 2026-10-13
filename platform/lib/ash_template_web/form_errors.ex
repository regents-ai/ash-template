defmodule AshTemplateWeb.FormErrors do
  @moduledoc """
  The words an Ash form shows under a field once the person has used it, and
  the same words for an API refusal: one line per rule the input broke.
  """

  import Phoenix.Component, only: [used_input?: 1]

  @spec messages(Phoenix.HTML.FormField.t()) :: [String.t()]
  def messages(field) do
    if used_input?(field), do: Enum.map(field.errors, &message/1), else: []
  end

  @doc "Each refused field of `error` and why, worded as the page's own form shows it."
  @spec details(Ash.Error.Invalid.t()) :: [%{field: atom(), message: String.t()}]
  def details(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.filter(&AshPhoenix.FormData.Error.impl_for/1)
    |> Enum.flat_map(&List.wrap(AshPhoenix.FormData.Error.to_form_error(&1)))
    |> Enum.map(fn {field, message, values} ->
      %{field: field, message: message({message, values})}
    end)
  end

  defp message({message, values}) do
    Enum.reduce(values, message, fn {key, value}, message ->
      String.replace(message, "%{#{key}}", to_string(value))
    end)
  end
end
