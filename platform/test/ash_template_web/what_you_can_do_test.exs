defmodule AshTemplateWeb.WhatYouCanDoTest do
  use ExUnit.Case, async: true

  import Plug.Test, only: [conn: 2]

  # The agent documents list, for every status, exactly what whoami answers.
  test "every agent document lists what whoami allows in each status and its next step" do
    allowed = Application.fetch_env!(:regent_agents, :allowed)

    for path <- ["/llms.txt", "/agents.md", "/skill.md"] do
      response =
        :get |> conn(path) |> AshTemplateWeb.Endpoint.call(AshTemplateWeb.Endpoint.init([]))

      assert response.status == 200

      for {status, lines} <- allowed do
        [_, block] = String.split(response.resp_body, "**`#{status}`**", parts: 2)
        [block | _] = String.split(block, "\n", parts: 2)
        assert Enum.all?(lines, &String.contains?(block, &1)), "#{path} #{status}"

        if next = RegentAgents.HTTP.next_step(status),
          do: assert(String.contains?(block, next), "#{path} #{status}")
      end
    end
  end
end
