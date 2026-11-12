defmodule AshTemplate.Markdown do
  @moduledoc "Markdown to HTML. Every page and message on the site renders through here."

  @doc """
  `MDEx.to_html!/2` with the site's one setting: text in braces right after inline
  code stays in the text. MDEx would read `` `run`{limit: 3} `` as attributes for the
  code and drop them.
  """
  def to_html!(markdown, options \\ []), do: MDEx.to_html!(markdown, with_setting(options))

  @doc "`MDEx.parse_document!/2` with the same setting, for a page that changes the tree before rendering it."
  def parse!(markdown, options \\ []), do: MDEx.parse_document!(markdown, with_setting(options))

  defp with_setting(options) do
    {extension, options} = Keyword.pop(options, :extension, [])
    [{:extension, Keyword.put(extension, :inline_code_attributes, false)} | options]
  end
end
