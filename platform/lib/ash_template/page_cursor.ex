defmodule AshTemplate.PageCursor do
  @moduledoc """
  Whether a paged read failed only because of the cursor it was given: an
  `after` that is not the previous page's cursor, unchanged.
  """

  @spec invalid?(term()) :: boolean()
  def invalid?(%Ash.Error.Action.InvalidArgument{field: :after}), do: true
  def invalid?(%Ash.Error.Page.InvalidKeyset{}), do: true
  def invalid?(%Ash.Error.Invalid{errors: [_ | _] = errors}), do: Enum.all?(errors, &invalid?/1)
  def invalid?(_error), do: false
end
