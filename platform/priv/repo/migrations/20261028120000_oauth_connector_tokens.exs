defmodule AshTemplate.Repo.Migrations.OAuthConnectorTokens do
  @moduledoc """
  The Claude connector's tokens, in this product's schema (`oauth_tokens`).

  1. New tokens are bound to the site's own address: the issuer and resource
     columns default to what `config/runtime.exs` sets for `AshTemplate.OAuth`
     from the site's host (`https://PHX_HOST` and its `/mcp` in production), and
     a token whose columns differ from the running site's is refused. Only the
     defaults change; no stored token's binding is rewritten, so tokens issued
     for the old resource (the bare origin) stay refused.
  2. `RegentOAuth.Migration.V2` replaces every stored access and refresh token
     with its SHA-256 hash, so an app connected before it keeps working with the
     tokens it holds and no plain token stays in the table.

  Up only: a hash does not give back its token. Step 2 rewrites existing rows,
  so on the shared production database it runs only with the founder's go.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    config = Application.fetch_env!(:ash_template, AshTemplate.OAuth)
    issuer = address!(config[:issuer])
    resource = address!(config[:resource])

    prefix = prefix() || repo().config()[:migration_default_prefix]
    table = if prefix, do: ~s("#{prefix}".oauth_tokens), else: "oauth_tokens"

    execute("""
    ALTER TABLE #{table}
      ALTER COLUMN oauth_issuer SET DEFAULT '#{issuer}',
      ALTER COLUMN mcp_resource SET DEFAULT '#{resource}'
    """)

    RegentOAuth.Migration.V2.up()
  end

  # Only a plain web address reaches the SQL above.
  @address ~r{\Ahttps?://[a-z0-9.-]+(:[0-9]+)?(/mcp)?\z}

  defp address!(address) do
    unless is_binary(address) and Regex.match?(@address, address) do
      raise "The site's address is unknown or not plain: set PHX_HOST before running this migration"
    end

    address
  end
end
