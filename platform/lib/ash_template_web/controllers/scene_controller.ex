defmodule AshTemplateWeb.SceneController do
  @moduledoc """
  Each scene of the Scenes page (`AshTemplateWeb.Scenes`) on its own: its page, the
  scene alone filling whatever frame it is shown in, and its trait file.

  The page is plain HTML with its own small script, `assets/js/scene_page.ts`: no
  session, no forms token, no live connection and nothing about the visitor, so any
  site can show it in a frame, sandboxed with scripts allowed or not sandboxed at all
  (the router's `:scene_page` pipeline lets any site frame it). Its stylesheet, its
  script, its still and its scene file are named by their full addresses, the script
  is a classic one rather than a module, and the scene files are open to every origin
  (`AshTemplateWeb.Endpoint`), so a sandboxed frame, whose origin is no site's, still
  loads them all.

  The trait file is open to every origin too (the `:scene_traits` pipeline).
  """

  use AshTemplateWeb, :controller

  alias AshTemplateWeb.Scenes

  def show(conn, %{"number" => number}), do: render(conn, :show, scene: Scenes.fetch!(number))

  def metadata(conn, %{"number" => number}),
    do: json(conn, number |> Scenes.fetch!() |> Scenes.metadata())
end
