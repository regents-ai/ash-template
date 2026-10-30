defmodule AshTemplateWeb.AgentPictureController do
  @moduledoc """
  The picture a person chose for their agent, by the agent's wallet, for
  anyone. Pages link it with `?v=` set to when it was last set (`path/2`), and
  only that link may be kept, for a day. Removing or replacing a picture
  answers every new request at once, but a browser or cache that already holds
  the old link may show the old picture for up to a day.
  """
  use AshTemplateWeb, :controller

  @doc """
  Where the picture of the agent at `wallet`, last set at `updated_at`, is
  shown from, or nil when it has none.
  """
  def path(_wallet, nil), do: nil

  def path(wallet, updated_at),
    do: "/agents/#{wallet}/picture?v=#{DateTime.to_unix(updated_at, :microsecond)}"

  # sobelow_skip ["XSS.SendResp"]
  def show(conn, %{"wallet" => wallet} = params) do
    with true <- wallet =~ ~r/\A0x[0-9a-fA-F]{40}\z/,
         {:ok, %RegentAgents.AgentPicture{} = picture} <-
           RegentAgents.agent_picture(String.downcase(wallet)) do
      conn
      |> put_resp_content_type("image/webp", nil)
      |> put_resp_header("cache-control", cache(params["v"], picture.updated_at))
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_resp(200, picture.bytes)
    else
      _none -> send_resp(conn, :not_found, "Not found")
    end
  end

  defp cache(version, updated_at) do
    if version == to_string(DateTime.to_unix(updated_at, :microsecond)),
      do: "public, max-age=86400",
      else: "public, max-age=0, must-revalidate"
  end
end
