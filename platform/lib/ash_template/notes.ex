defmodule AshTemplate.Notes do
  @moduledoc """
  Notes a signed-in person writes for themselves, from the page or the API, and
  the labels Jev gives them. What an agent does with its person's notes is also
  a hosted agent tool (`tools`).
  """

  use Ash.Domain, otp_app: :ash_template, extensions: [AshAi, AshPhoenix]

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

      define :notes_list, action: :notes_list
      define :notes_get, action: :notes_get, args: [:id]
      define :notes_search, action: :notes_search, args: [:text]
      define :notes_create, action: :notes_create
      define :notes_edit, action: :notes_edit, args: [:id]
      define :notes_delete, action: :notes_delete, args: [:id]
      define :notes_pin_price, action: :notes_pin_price, args: [:id]
      define :notes_unpin, action: :notes_unpin, args: [:id]
      define :notes_archive, action: :notes_archive, args: [:id]
      define :notes_unarchive, action: :notes_unarchive, args: [:id]
    end

    resource AshTemplate.Notes.Decision do
      define :get_label_decision, action: :read, get_by: [:id], not_found_error?: false
      define :rate_label, action: :report, args: [:report]
      define :notes_rate_label, action: :notes_rate_label, args: [:id]
    end
  end

  # The hosted agent tools: each runs the same action as its HTTP route, its
  # browser tool and its regents-cli command, and is named after them
  # (`AshTemplateWeb.Capabilities` checks both).
  tools do
    tool :notes_list, AshTemplate.Notes.Note, :notes_list do
      description AshTemplate.Descriptions.hosted(:notes_list)
    end

    tool :notes_get, AshTemplate.Notes.Note, :notes_get do
      description AshTemplate.Descriptions.hosted(:notes_get)
    end

    tool :notes_search, AshTemplate.Notes.Note, :notes_search do
      description AshTemplate.Descriptions.hosted(:notes_search)
    end

    tool :notes_create, AshTemplate.Notes.Note, :notes_create do
      description AshTemplate.Descriptions.hosted(:notes_create)
    end

    tool :notes_edit, AshTemplate.Notes.Note, :notes_edit do
      description AshTemplate.Descriptions.hosted(:notes_edit)
    end

    tool :notes_delete, AshTemplate.Notes.Note, :notes_delete do
      description AshTemplate.Descriptions.hosted(:notes_delete)
    end

    tool :notes_pin_price, AshTemplate.Notes.Note, :notes_pin_price do
      description AshTemplate.Descriptions.hosted(:notes_pin_price)
    end

    tool :notes_unpin, AshTemplate.Notes.Note, :notes_unpin do
      description AshTemplate.Descriptions.hosted(:notes_unpin)
    end

    tool :notes_archive, AshTemplate.Notes.Note, :notes_archive do
      description AshTemplate.Descriptions.hosted(:notes_archive)
    end

    tool :notes_unarchive, AshTemplate.Notes.Note, :notes_unarchive do
      description AshTemplate.Descriptions.hosted(:notes_unarchive)
    end

    tool :notes_rate_label, AshTemplate.Notes.Decision, :notes_rate_label do
      description AshTemplate.Descriptions.hosted(:notes_rate_label)
    end
  end
end
