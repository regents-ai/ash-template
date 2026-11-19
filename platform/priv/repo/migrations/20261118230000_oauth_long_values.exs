defmodule AshTemplate.Repo.Migrations.OAuthLongValues do
  @moduledoc """
  Connected apps may send values longer than 255 characters: OpenAI's apps send
  a `state` that long, which Allow could not store. `RegentOAuth.Migration.V4`
  lifts that limit from a code's `state` and callback and from an app's name,
  callbacks and keys address.

  No row changes and no table is rewritten: each column only loses its length
  limit. Each table is locked while its definition changes.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    RegentOAuth.Migration.V4.up()
  end
end
