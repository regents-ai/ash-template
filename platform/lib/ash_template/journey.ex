defmodule AshTemplate.Journey do
  @moduledoc """
  This site's value action, heard from the signal its own domain emits and
  written as a visit-log `step` (`AshTemplate.Journey.Value`). It stores nothing.
  """

  use Ash.Domain

  resources do
    resource AshTemplate.Journey.Value
  end
end
