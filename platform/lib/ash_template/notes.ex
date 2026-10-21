defmodule AshTemplate.Notes do
  @moduledoc "Notes a signed-in person writes for themselves, from the page or the API."

  use Ash.Domain, extensions: [AshPhoenix]

  resources do
    resource AshTemplate.Notes.Note do
      define :list_my_notes,
        action: :mine,
        default_options: [load: [:label_decision, :changed_by_agent]]

      define :search_my_notes, action: :search, args: [:text]

      define :get_my_note,
        action: :read,
        get_by: [:id],
        not_found_error?: false,
        default_options: [load: [:label_decision, :changed_by_agent]]

      define :create_note,
        action: :create,
        default_options: [load: [:label_decision, :changed_by_agent]]

      define :update_note,
        action: :update,
        default_options: [load: [:label_decision, :changed_by_agent]]

      define :pin_note,
        action: :pin,
        args: [:operation_id],
        default_options: [load: [:label_decision, :changed_by_agent]]

      define :unpin_note,
        action: :unpin,
        default_options: [load: [:label_decision, :changed_by_agent]]

      define :archive_note,
        action: :archive,
        default_options: [load: [:label_decision, :changed_by_agent]]

      define :unarchive_note,
        action: :unarchive,
        default_options: [load: [:label_decision, :changed_by_agent]]

      define :destroy_note, action: :destroy
    end

    resource AshTemplate.Notes.Decision do
      define :get_label_decision, action: :read, get_by: [:id], not_found_error?: false
      define :rate_label, action: :report, args: [:report]
    end
  end

  @doc """
  The note the actor's person already has under this `operation_id`, which is
  the note's id, so a retry answers the first create: `{:ok, note}`, or
  `{:ok, nil}` when there is none or the id is missing or malformed.
  """
  def earlier_note(nil, _opts), do: {:ok, nil}

  def earlier_note(operation_id, opts) do
    case get_my_note(operation_id, opts) do
      {:error, %Ash.Error.Invalid{}} -> {:ok, nil}
      result -> result
    end
  end
end
