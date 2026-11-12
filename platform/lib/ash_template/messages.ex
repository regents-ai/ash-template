defmodule AshTemplate.Messages do
  @moduledoc """
  Messages left for the site's team: a signed agent or a signed-in person leaves
  one under a topic the site names, such as `agents`, and only the site's admins
  read them (`/admin/messages`). Nobody else ever sees one. Leaving a message is
  also a hosted agent tool (`tools`).
  """

  use Ash.Domain, otp_app: :ash_template, extensions: [AshAi, AshPhoenix]

  resources do
    resource AshTemplate.Messages.Message do
      define :leave_message, action: :leave
      define :agent_leave_message, action: :agent_leave, args: [:topic]
      define :list_messages, action: :newest
      define :get_message, action: :read, get_by: [:id], not_found_error?: false
    end
  end

  # The hosted agent tool: it runs the same action as its HTTP route, its browser
  # tool and its regents-cli command, and is named after them
  # (`AshTemplateWeb.Capabilities` checks both).
  tools do
    tool :messages_leave, AshTemplate.Messages.Message, :agent_leave do
      description "Leave a private message for this site's team under a topic, such as agents. Only the team reads it; nobody else sees it. Say in reply_to where you want an answer. Keep operation_id when retrying: a retry answers the first message. Works before you are paired."
    end
  end
end
