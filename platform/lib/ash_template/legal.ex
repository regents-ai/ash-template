defmodule AshTemplate.Legal do
  @moduledoc "The Privacy Policy and Terms of Use as committed Markdown."

  @privacy_path Application.app_dir(:ash_template, "priv/legal/privacy.md")
  @terms_path Application.app_dir(:ash_template, "priv/legal/terms.md")
  @external_resource @privacy_path
  @external_resource @terms_path

  @sources %{privacy: File.read!(@privacy_path), terms: File.read!(@terms_path)}

  def markdown(id) when is_map_key(@sources, id), do: @sources[id]
end
