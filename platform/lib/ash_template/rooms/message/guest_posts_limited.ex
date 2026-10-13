defmodule AshTemplate.Rooms.Message.GuestPostsLimited do
  @moduledoc """
  The address has used its hourly allowance of posts no person stands behind;
  `retry_after` is the seconds left of the hour.
  """
  use Splode.Error, fields: [:retry_after], class: :forbidden

  def message(_error),
    do: "This network has already posted as many messages without a person as it may this hour."
end
