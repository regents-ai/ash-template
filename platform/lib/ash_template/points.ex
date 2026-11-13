defmodule AshTemplate.Points do
  @moduledoc """
  This site's part in Regent Points: what it offers Points, as it happens, and
  one account's Points as its page and its agent show them.
  """

  use Ash.Domain

  resources do
    resource AshTemplate.Points.Award

    resource AshTemplate.Points.Standing do
      define :my_points, action: :mine
    end
  end
end
