defmodule AshTemplateWeb.Components.AgentMessage do
  @moduledoc """
  The Agent Message button and its dialog: three texts a visitor pastes into
  their agent so it leaves a private message for the site's team under a
  `topic` the site names, through the regents CLI, the hosted MCP server or the
  site's WebMCP tool. Each names this site's address and the command and tools
  read when this module compiles from `cli/commands.json` and
  `priv/tool_manifest.json`, the files every surface is checked against
  (`AshTemplateWeb.Capabilities`), so the texts cannot name a command that is
  not there. `texts/1` gives them to any page or document that tells an agent
  how.

  Below the texts, a signed-in person leaves a message themselves
  (`AshTemplateWeb.Components.AgentMessage.Form`); a signed-out visitor sees only
  the texts.
  """

  use Phoenix.Component

  alias AshTemplateWeb.PublicDocuments

  commands = Path.expand("../../../../cli/commands.json", __DIR__)
  manifest = Application.app_dir(:ash_template, "priv/tool_manifest.json")
  @external_resource commands
  @external_resource manifest

  %{"platform" => platform, "commands" => commands} = commands |> File.read!() |> Jason.decode!()
  %{"command" => command} = Enum.find(commands, &(&1["operation_id"] == "leaveMessage"))

  %{"name" => tool} =
    manifest
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("tools")
    |> Enum.find(&(&1["operation_id"] == "leaveMessage"))

  # `messages leave <topic>`, with the topic left for `texts/1` to fill in.
  @command "regents #{platform} " <> String.replace(command, "<topic>", "")
  @tool tool

  @doc """
  The three paste-ready texts for leaving a message under `topic`, each with its
  one- or two-word title: the CLI line, the hosted MCP tool call and the WebMCP
  tool call, with this site's address and names filled in.
  """
  @spec texts(String.t()) :: [%{id: String.t(), title: String.t(), text: String.t()}]
  def texts(topic) do
    site = PublicDocuments.url("")

    input = fn first ->
      Jason.encode!(
        Jason.OrderedObject.new(
          first ++
            [
              body: "<your message>",
              reply_to: "<where to answer you>",
              operation_id: "<a new UUID>"
            ]
        ),
        pretty: true
      )
    end

    [
      %{
        id: "cli",
        title: "CLI",
        text: """
        Leave a message for the team at #{site} with the regents CLI, signed as you:

        echo '#{Jason.encode!(Jason.OrderedObject.new(body: "<your message>", reply_to: "<where to answer you>", operation_id: "<a new UUID>"))}' | #{@command}#{topic}

        Keep the same operation_id if you retry. Only the team reads it.\
        """
      },
      %{
        id: "mcp",
        title: "MCP",
        text: """
        Leave a message for the team at #{site} with its hosted MCP server, #{site}/mcp. Call its #{@tool} tool with this input, signed by your agent (regents mcp --site #{AshTemplate.site()} signs each call for you):

        #{input.(topic: topic)}

        Keep the same operation_id if you retry. Only the team reads it.\
        """
      },
      %{
        id: "webmcp",
        title: "WebMCP",
        text: """
        Open #{site} in your browser and call the WebMCP tool #{@tool}, signed with your agent key, with this input:

        #{input.(topic: topic)}

        Keep the same operation_id if you retry. Only the team reads it.\
        """
      }
    ]
  end

  attr :id, :string, required: true
  attr :dialog, :string, required: true, doc: "The id of the `dialog/1` it opens."
  attr :class, :any, default: nil

  @doc "The Agent Message button, which opens its dialog."
  def button(assigns) do
    ~H"""
    <Regent.Primitives.button
      id={@id}
      variant="secondary"
      arrow={false}
      class={["agent-message-button", @class]}
      aria-haspopup="dialog"
      aria-controls={@dialog}
      data-agent-message-open
    >
      <Regent.Icons.icon name="bot-message-square" /> Agent Message
    </Regent.Primitives.button>
    """
  end

  attr :id, :string, required: true
  attr :topic, :string, required: true, doc: "The topic its messages are left under."

  attr :account, :map, default: nil, doc: "The signed-in account, or nil."
  attr :lease, :map, default: nil, doc: "The page's `session_lease`."
  attr :client_key, :string, default: nil, doc: "The page's `client_key`."

  @doc """
  The dialog: the three texts, each with its copy button, and for a signed-in
  person the form that leaves a message (`AgentMessage.Form`). Closed with its X,
  Escape or a press beside it (`assets/js/agent_message.ts`). The page passes its
  signed-in `account`, `session_lease` as `lease` and `client_key`, and the form
  runs in it.
  """
  def dialog(assigns) do
    assigns = assign(assigns, texts: texts(assigns.topic), form: "#{assigns.id}-person")

    ~H"""
    <Regent.Structure.dialog
      id={@id}
      class="code-card agent-message"
      aria-labelledby={"#{@id}-title"}
      data-agent-message
    >
      <header class="code-card__head">
        <h2 id={"#{@id}-title"}>Agent Message</h2>
        <button type="button" class="code-card__close" aria-label="Close" data-agent-message-close>
          <Regent.Icons.icon name="x" />
        </button>
      </header>
      <div class="code-card__body">
        <p class="code-card__note">
          Paste one of these into your agent. It leaves a private message that only this site's team reads.
        </p>
        <ol class="code-card__list">
          <li :for={text <- @texts} class="code-card__tool agent-message__text">
            <div class="agent-message__head">
              <h3>{text.title}</h3>
              <Regent.Primitives.copy_button
                id={"#{@id}-copy-#{text.id}"}
                variant="secondary"
                target={"#{@id}-text-#{text.id}"}
              >
                Copy
              </Regent.Primitives.copy_button>
            </div>
            <pre><code id={"#{@id}-text-#{text.id}"}>{text.text}</code></pre>
          </li>
        </ol>
        <.live_component
          module={AshTemplateWeb.Components.AgentMessage.Form}
          id={@form}
          topic={@topic}
          account={@account}
          lease={@lease}
          client_key={@client_key}
        />
      </div>
    </Regent.Structure.dialog>
    """
  end
end
