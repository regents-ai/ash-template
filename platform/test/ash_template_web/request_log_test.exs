defmodule AshTemplateWeb.RequestLogTest do
  # A request's logged parameters never carry the signed payment an agent sends to
  # pin a note, wherever it sits in the body.
  use ExUnit.Case, async: true

  test "a signed payment is never logged, at the top of a body or inside it" do
    payment = "eyJ4NDAyVmVyc2lvbiI6Mn0"

    logged =
      Phoenix.Logger.filter_values(%{
        "payment" => payment,
        "pin" => %{"payment" => payment},
        "text" => "kept"
      })

    refute inspect(logged) =~ payment
    assert logged["text"] == "kept"
  end
end
