defmodule AshTemplateWeb.ReadTest do
  use ExUnit.Case, async: true

  alias AshTemplateWeb.Read

  # A page's own database reads land in the first render with `Read.now`, and
  # a refused read is shown as a failure, never as an empty list.
  test "a read of the site's own database lands in the same callback" do
    socket = socket() |> Read.now(:notes, 1, fn -> {:ok, ["first note"]} end)

    assert %Read{state: :ready, value: ["first note"], owner: 1, read_at: %DateTime{}} =
             socket.assigns.notes
  end

  test "a database that refuses the read lands as a failure, never as empty" do
    refused = fn -> raise DBConnection.ConnectionError, "refused" end

    failed = socket() |> Read.now(:notes, 1, refused)
    assert %Read{state: :error, value: nil} = failed.assigns.notes

    kept =
      socket()
      |> Read.now(:notes, 1, fn -> {:ok, ["first note"]} end)
      |> Read.now(:notes, 1, refused)

    assert %Read{state: :stale, value: ["first note"]} = kept.assigns.notes
  end

  test "another owner's read starts from nothing and drops a read still running" do
    socket =
      socket()
      |> Read.now(:notes, 1, fn -> {:ok, ["first note"]} end)
      |> Read.now(:notes, 2, fn -> {:ok, []} end)

    assert %Read{state: :empty, value: [], owner: 2, generation: 2} = socket.assigns.notes

    late = Read.settle(socket, {Read, :notes, 1}, {:ok, {:ok, ["first note"]}})
    assert late.assigns.notes == socket.assigns.notes
  end

  defp socket, do: %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, notes: %Read{}}}
end
