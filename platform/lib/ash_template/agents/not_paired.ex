defmodule AshTemplate.Agents.NotPaired do
  @moduledoc """
  An agent acting as itself where only an agent acting for its person may go,
  named by what it is missing: `agent_not_paired` when no person paired it, or
  `person_not_here` when its person has not signed in on this site yet. Every
  surface answers it in the same words
  (`AshTemplateWeb.Plugs.AgentWallet.not_person_refusals/0`).
  """
  use Splode.Error, fields: [:code], class: :forbidden

  alias AshTemplate.Actors.{Agent, Human}

  def message(%{code: code}), do: "Refused: #{code}"

  @doc "The refusal code for an agent that does not act for its person."
  @spec code(Agent.t()) :: String.t()
  def code(%Agent{pairing: :none}), do: "agent_not_paired"
  def code(%Agent{pairing: :person_not_here}), do: "person_not_here"

  @doc """
  `:ok` for a person, or for an agent while it acts for its person; otherwise this
  refusal naming what the agent is missing.
  """
  @spec check(Agent.t() | Human.t()) :: :ok | {:error, Exception.t()}
  def check(%Human{}), do: :ok
  def check(%Agent{pairing: :active}), do: :ok
  def check(%Agent{} = actor), do: {:error, exception(code: code(actor))}

  @doc """
  A write's `result`, with the refusal of an agent whose pairing ended after its
  request was let in, which the write's own policy (`RegentAgents.Checks.Paired`)
  then forbade, named `agent_not_paired`, as every surface answers it.
  """
  @spec ended(term()) :: term()
  def ended({:error, %Ash.Error.Forbidden{}}), do: {:error, exception(code: "agent_not_paired")}
  def ended(result), do: result
end
