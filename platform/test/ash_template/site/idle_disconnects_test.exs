defmodule AshTemplate.IdleDisconnectsTest do
  # The database closing an idle connection is routine (Sentinel's error-log
  # survey, 15 Oct: it filled the error level on every site); a real disconnect
  # still logs at error.
  use ExUnit.Case, async: true

  alias AshTemplate.IdleDisconnects

  defp disconnect(reason),
    do: %{
      level: :error,
      msg:
        {:string,
         [
           "Postgrex.Protocol",
           " (",
           "#PID<0.1.0>",
           ") disconnected: " | "** (DBConnection.ConnectionError) #{reason}"
         ]},
      meta: %{mfa: {DBConnection.Connection, :handle_event, 4}}
    }

  test "an idle connection the database closed is logged at info" do
    assert %{level: :info} = IdleDisconnects.filter(disconnect("ssl recv (idle): closed"), nil)
  end

  test "any other disconnect stays an error" do
    assert %{level: :error} = IdleDisconnects.filter(disconnect("ssl recv: closed"), nil)
    assert %{level: :error} = IdleDisconnects.filter(disconnect("ssl recv (idle): timeout"), nil)
  end
end
