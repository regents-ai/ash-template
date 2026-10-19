defmodule AshTemplateWeb.CreditsHistoryRefreshTest do
  # Invariant: when the history is read again after a change, the older pages a
  # person already opened stay, so the list is what reading every page again
  # would show, newest first with nothing twice. When the new first page no
  # longer reaches them, only the new first page shows, with Show older after it.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AshTemplateWeb.CreditsHistoryLive

  @page 50

  property "a refreshed history keeps the older pages shown" do
    check all(
            total <- integer(1..200),
            opened <- integer(1..4),
            added <- integer(0..120)
          ) do
      before = Enum.to_list(total..1//-1)
      shown = Enum.reduce(2..opened//1, page(before, nil), &more(before, &2, &1))
      now = Enum.to_list((total + added)..1//-1)
      fresh = page(now, nil)

      refreshed = CreditsHistoryLive.refreshed(fresh, shown)
      ids = Enum.map(refreshed.entries, & &1.id)

      assert ids == Enum.uniq(ids)
      assert ids == Enum.sort(ids, :desc)
      assert Enum.take(ids, length(fresh.entries)) == Enum.map(fresh.entries, & &1.id)

      reaches? = fresh.more? and Enum.member?(shown.entries, List.last(fresh.entries))

      if reaches? do
        assert ids == Enum.take(now, added + length(shown.entries))
        assert refreshed.more? == shown.more?
        assert refreshed.next == shown.next
      else
        assert refreshed == fresh
      end
    end
  end

  # Pages as the library reads them: newest first, at most fifty, `next` being
  # the last id read.
  defp page(ids, after_id) do
    rest = if after_id, do: Enum.drop_while(ids, &(&1 >= after_id)), else: ids
    {entries, left} = Enum.split(rest, @page)

    %{
      entries: Enum.map(entries, &%{id: &1}),
      more?: left != [],
      next: List.last(entries)
    }
  end

  defp more(ids, %{more?: true} = shown, _n) do
    next = page(ids, shown.next)
    %{next | entries: shown.entries ++ next.entries}
  end

  defp more(_ids, shown, _n), do: shown
end
