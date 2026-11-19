defmodule AshTemplateWeb.SceneHTML do
  @moduledoc """
  A scene's own page (`AshTemplateWeb.SceneController`): the shared stage alone
  (`AshTemplateWeb.Components.SplatStage.stage/1`), filling the page on the scene's
  own sky, with its zoom buttons small in the corner once it has drawn. No header,
  footer, title or traits, and no Download GIF. The head carries the link preview: the
  title, the line and the card picture (1440 by 960) as a large picture, and the
  feedback tool's entry, which the page's script offers to a browser agent.
  """

  use AshTemplateWeb, :html

  alias AshTemplateWeb.Components.{AgentTools, SplatStage}
  alias AshTemplateWeb.{Endpoint, PublicDocuments, Scenes}

  def show(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" style={"--scene-sky: #{@scene.sky}"}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@scene.title} · Ash Template</title>
        <Regent.AgentMetadata.head
          title={@scene.title}
          description={@scene.description}
          canonical={Scenes.page_url(@scene)}
          site_name="Ash Template"
          image={Scenes.still_url(@scene, :card)}
          image_width={1440}
          image_height={960}
          image_alt={@scene.description}
          twitter_site="@regents_sh"
          structured_data={PublicDocuments.structured_data([])}
        />
        <link rel="stylesheet" href={url(~p"/assets/js/scene_page.css")} />
        <AgentTools.feedback />
        <script defer src={url(~p"/assets/js/scene_page.js")}>
        </script>
      </head>
      <body>
        <SplatStage.stage
          id={"scene-#{@scene.number}"}
          class="scene-page"
          scene={@scene.name}
          label={"#{@scene.title}. #{@scene.description}"}
          file={full(Scenes.file(@scene))}
          still={full(Scenes.still(@scene, :wide))}
        />
      </body>
    </html>
    """
  end

  defp full(path), do: Endpoint.static_url() <> path
end
