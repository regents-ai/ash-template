defmodule AshTemplateWeb.SignedBodyReader do
  @moduledoc """
  Keeps the exact bytes of every body the API takes, so the sign-in service can
  check them against the request's signature (`AshTemplateWeb.Plugs.AgentWallet`,
  `RegentAgents.HTTP`): any of them may come from an agent. The pages' own form
  bodies are read as before.
  """

  # The largest signed body is a note: 10,000 characters of text, as JSON.
  @limit 65_536

  def read_body(conn, opts) do
    if signed?(conn),
      do: Siwa.AgentAuthPlug.read_body(conn, opts, @limit),
      else: RegentIdentity.BodyReader.read_body(conn, opts)
  end

  defp signed?(%{method: method, path_info: ["api" | _rest]}) when method in ["POST", "PATCH"],
    do: true

  defp signed?(_conn), do: false
end
