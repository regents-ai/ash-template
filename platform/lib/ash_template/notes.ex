defmodule AshTemplate.Notes do
  @moduledoc "Notes a signed-in person writes for themselves, from the page or the API."

  use Ash.Domain

  resources do
    resource AshTemplate.Notes.Note do
      define :list_my_notes, action: :mine, default_options: [load: [:label_decision]]
      define :search_my_notes, action: :search, args: [:text]

      define :get_my_note,
        action: :read,
        get_by: [:id],
        not_found_error?: false,
        default_options: [load: [:label_decision]]

      define :create_note, action: :create
      define :update_note, action: :update
      define :destroy_note, action: :destroy
    end

    resource AshTemplate.Notes.Decision do
      define :get_label_decision, action: :read, get_by: [:id], not_found_error?: false
      define :rate_label, action: :report, args: [:report]
    end
  end
end
