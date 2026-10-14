defmodule AshTemplate.Rooms.Signals do
  @moduledoc """
  What the rooms tell the rest of the site, as Ash signals. Each is emitted in
  the post's own transaction, so a listener with the default delivery commits
  or rolls back with it.

    * `:message_posted`: a message was posted in a room. Activity tells the
      people it mentions (`AshTemplate.Activity.Notification`).
  """

  use Ash.Signals

  signals do
    signal :message_posted do
      argument :message_id, :uuid, allow_nil?: false
    end
  end
end
