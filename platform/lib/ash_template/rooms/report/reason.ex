defmodule AshTemplate.Rooms.Report.Reason do
  @moduledoc """
  Why a person reports a room message: spam, abuse, text that tries to steer
  agents, or something else.
  """

  use Ash.Type.Enum, values: [:spam, :abuse, :steers_agents, :other]
end
