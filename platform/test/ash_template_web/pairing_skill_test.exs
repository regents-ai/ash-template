defmodule AshTemplateWeb.PairingSkillTest do
  # The pairing message sends every agent to its own skill on this site for the
  # rest of the steps (RegentAgents.PairingMessage). Each agent a person can pick,
  # and any agent naming another harness, must land on a skill this site serves
  # that holds the steps the message names, with where the agent's key lives.
  use ExUnit.Case, async: true

  import Plug.Test, only: [conn: 2]

  alias RegentAgents.{Harness, PairingMessage}

  test "every agent's pairing message links to a served skill with the steps it names" do
    origin = AshTemplateWeb.Endpoint.url()

    for harness <- Harness.values() -- Harness.hosted_runtimes() do
      [_, link] =
        "ABCD-1234"
        |> PairingMessage.text(origin, harness)
        |> String.split(~s(steps in ), parts: 2)

      response =
        :get
        |> conn(String.replace_prefix(link, origin, ""))
        |> AshTemplateWeb.Endpoint.call(AshTemplateWeb.Endpoint.init([]))

      assert response.status == 200, "#{harness}: #{link}"
      assert [_, steps] = String.split(response.resp_body, "\n## Pair with a person's account\n")
      assert steps =~ "SIWA_AGENT_HOME=", "#{harness}"
    end
  end
end
