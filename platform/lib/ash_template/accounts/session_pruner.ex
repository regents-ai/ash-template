defmodule AshTemplate.Accounts.SessionPruner do
  @moduledoc """
  Deletes, once a day, the sign-in session rows no browser can still hold
  (`AshTemplate.Accounts.SessionAuthority.prune/0`). Every visitor without a
  cookie gets a row, and revoked and lapsed rows stay behind, so without this
  the table only grows.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias AshTemplate.Accounts.SessionAuthority

  @impl Oban.Worker
  def perform(_job) do
    with {:ok, _pruned} <- SessionAuthority.prune(), do: :ok
  end
end
