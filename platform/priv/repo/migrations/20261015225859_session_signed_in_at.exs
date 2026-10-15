defmodule AshTemplate.Repo.Migrations.SessionSignedInAt do
  @moduledoc """
  A sign-in ends 30 days after it was made, so a bound lineage records when.
  """

  use Ecto.Migration

  # A sign-in already bound counts from its last refresh, the closest record of it.
  def up do
    alter table(:session_authorities) do
      add(:signed_in_at, :utc_datetime_usec)
    end

    execute(
      "UPDATE #{prefix()}.session_authorities SET signed_in_at = updated_at WHERE human_account_id IS NOT NULL"
    )

    create constraint(:session_authorities, :session_authorities_signed_in_when_bound,
             check: """
               (human_account_id IS NULL) = (signed_in_at IS NULL)
             """
           )
  end

  def down do
    drop_if_exists(constraint(:session_authorities, :session_authorities_signed_in_when_bound))

    alter table(:session_authorities) do
      remove(:signed_in_at)
    end
  end
end
