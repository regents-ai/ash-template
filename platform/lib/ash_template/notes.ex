defmodule AshTemplate.Notes do
  @moduledoc "Notes a signed-in person writes for themselves, from the page or the API."

  use Ash.Domain

  resources do
    resource AshTemplate.Notes.Note do
      define :list_my_notes, action: :mine
      define :get_my_note, action: :read, get_by: [:id], not_found_error?: false
      define :create_note, action: :create
      define :update_note, action: :update
      define :destroy_note, action: :destroy
    end
  end
end
