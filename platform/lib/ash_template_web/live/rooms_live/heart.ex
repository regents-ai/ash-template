defmodule AshTemplateWeb.RoomsLive.Heart do
  @moduledoc """
  A room message's heart and its count: the one part of a message on the page
  that changes without the message being drawn again, since the page keeps no
  messages once it has shown them (`AshTemplateWeb.RoomsLive`).

  The count comes from the message as drawn and from each like notice
  (`%{like_count, like_version}`, the message's own publication), and the
  higher `like_version` wins, since the two can arrive in either order. Whether
  the reader likes it (`liked`) changes only from their own press, which the
  room page hands on. A visitor's press opens sign-in.

  Its root carries `data-liked` while the reader likes the message, so the
  message's menu offers Remove like in place of Like. A count that changes
  while the reader watches rolls to its new figure (`MotionCount`); the first
  like's count and the last one taken back simply come and go.
  """

  use AshTemplateWeb, :live_component

  alias Regent.Discussion

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :message_id, :liked, :signed_in?, :target]))
     |> newer(assigns)}
  end

  defp newer(socket, %{like_count: count, like_version: version}) do
    if version > Map.get(socket.assigns, :like_version, -1),
      do: assign(socket, like_count: count, like_version: version),
      else: socket
  end

  defp newer(socket, _assigns), do: socket

  @impl true
  def render(%{signed_in?: false} = assigns) do
    ~H"""
    <div
      id={@id}
      class="rooms-heart"
      phx-hook="MotionCount"
      data-variant={AshTemplateWeb.Motion.standard("count")}
    >
      <Discussion.like
        :if={@like_count > 0}
        count={@like_count}
        liked={false}
        data-account-target="sign-in"
      />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="rooms-heart"
      data-liked={@liked}
      phx-hook="MotionCount"
      data-variant={AshTemplateWeb.Motion.standard("count")}
    >
      <Discussion.like
        :if={@like_count > 0}
        count={@like_count}
        liked={@liked}
        phx-click={JS.push("like", value: %{id: @message_id}, target: @target)}
      />
    </div>
    """
  end
end
