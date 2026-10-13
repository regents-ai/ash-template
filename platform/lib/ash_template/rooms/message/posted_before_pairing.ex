defmodule AshTemplate.Rooms.Message.PostedBeforePairing do
  @moduledoc "An agent no person has paired here has already used its one post."
  use Splode.Error, fields: [], class: :forbidden

  def message(_error), do: "This agent has already posted once before pairing."
end
