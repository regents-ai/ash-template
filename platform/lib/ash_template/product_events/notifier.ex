defmodule AshTemplate.ProductEvents.Notifier do
  @moduledoc """
  Writes `value_reached` for each of the site's value actions, once the action
  has committed (Ash sends notifications after the transaction), with the kind
  the site gave it and the actor's account and agent.

  A site names its value actions in config, each `{resource, action}` with its
  kind:

      config :ash_template, AshTemplate.ProductEvents,
        value_actions: %{{AshTemplate.Notes.Note, :create} => "note"}

  and adds this notifier to each resource it names
  (`notifiers: [AshTemplate.ProductEvents.Notifier]`). The resource's other
  actions write nothing.
  """

  use Ash.Notifier

  alias AshTemplate.ProductEvents

  @value_actions Application.compile_env!(:ash_template, [ProductEvents, :value_actions])

  @impl Ash.Notifier
  def notify(%Ash.Notifier.Notification{resource: resource, action: action, actor: actor}) do
    case Map.fetch(@value_actions, {resource, action.name}) do
      {:ok, kind} -> ProductEvents.record(:value_reached, actor, %{kind: kind})
      :error -> :ok
    end
  end
end
