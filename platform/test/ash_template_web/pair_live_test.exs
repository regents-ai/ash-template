defmodule AshTemplateWeb.PairLiveTest do
  # A pairing link's page is printed as a link and pasted to an agent, so only a
  # page on this site is taken; anything a browser could read as another site is
  # dropped and the link opens plain pairing.
  use ExUnit.Case, async: true

  alias AshTemplateWeb.PairLive

  test "a page on this site is where the agent starts" do
    for to <- ["/", "/rooms/general", "/polls/1?view=results#votes"],
        do: assert(PairLive.start(%{"to" => to}) == to)
  end

  test "anything else opens plain pairing" do
    for to <- [
          "//example.com",
          "/\\example.com",
          "https://example.com/rooms",
          "javascript:alert(1)",
          "rooms/general",
          "/rooms general",
          "/rooms\ngeneral",
          "/rooms\u0000",
          "",
          "/" <> String.duplicate("a", 512),
          ["/rooms"]
        ],
        do: assert(PairLive.start(%{"to" => to}) == nil, inspect(to))

    assert PairLive.start(%{}) == nil
  end
end
