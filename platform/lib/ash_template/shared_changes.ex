defmodule AshTemplate.SharedChanges do
  @moduledoc """
  Changes made on any Regent site reach this site's open pages: a pairing made or
  ended (`RegentAgents.Listener`) arrives as a database notice. It listens on one
  connection of the site's own outside the repository's pool,
  `AshTemplate.Notifications` (`AshTemplate.DatabaseConfig.notifications_config!/2`),
  since a connection in the pool goes back to it after each query. The connection
  starts first, so a new connection brings a new listener.
  """

  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    connection = Application.fetch_env!(:ash_template, AshTemplate.Notifications)

    children = [
      {Postgrex.Notifications, [name: AshTemplate.Notifications] ++ connection},
      RegentAgents.Listener
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
