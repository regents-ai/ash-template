defmodule AshTemplate.Rooms.Signals do
  @moduledoc """
  What the rooms tell the rest of the site, as Ash signals. Each is emitted in
  the post's own transaction, so a listener with the default delivery commits
  or rolls back with it.

    * `:message_posted`: a message was posted in a room, with its words, so a
      listener that has nothing to do with them returns without a read. Activity
      tells the people it mentions (`AshTemplate.Activity.Notification`).
  """

  use Ash.Signals

  signals do
    signal :message_posted do
      argument :message_id, :uuid, allow_nil?: false
      argument :body, :string, allow_nil?: false
    end
  end
end
