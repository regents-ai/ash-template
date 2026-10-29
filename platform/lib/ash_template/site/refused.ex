defmodule AshTemplate.Site.Refused do
  @moduledoc """
  A read of the site refused, named by the refusal `code` every surface answers
  with: `unavailable` when its database is not answering
  (`AshTemplateWeb.HealthController` holds its words), and `site_unreachable`
  when another site's tools could not be read (`AshTemplateWeb.SiteToolsController`).
  """
  use Splode.Error, fields: [:code], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
