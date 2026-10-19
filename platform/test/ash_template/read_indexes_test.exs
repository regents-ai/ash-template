defmodule AshTemplate.ReadIndexesTest do
  # Regression: every page count of unread notifications and every sign-in's
  # look-up of linked accounts read their whole table, since neither had an index.
  use ExUnit.Case, async: true

  @indexes """
  SELECT indexname, indexdef FROM pg_indexes
  WHERE schemaname = 'ash_template_app'
    AND indexname IN ('notifications_unread_index', 'linked_identities_human_account_id_index')
  ORDER BY indexname
  """

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "unread notifications and linked accounts are found by index" do
    %{rows: rows} = Ecto.Adapters.SQL.query!(AshTemplate.Repo, @indexes, [])

    assert [
             ["linked_identities_human_account_id_index", linked],
             ["notifications_unread_index", unread]
           ] = rows

    assert linked =~ "(human_account_id)"
    assert unread =~ "(human_account_id) WHERE (read_at IS NULL)"
  end
end
