defmodule AshTemplate.Markdown do
  @moduledoc "Markdown to HTML. Every page and message on the site renders through here."

  @doc """
  `MDEx.to_html!/2` with the site's one setting: text in braces right after inline
  code stays in the text. MDEx would read `` `run`{limit: 3} `` as attributes for the
  code and drop them.
  """
  def to_html!(markdown, options \\ []) do
    {extension, options} = Keyword.pop(options, :extension, [])

    MDEx.to_html!(markdown, [
      {:extension, Keyword.put(extension, :inline_code_attributes, false)} | options
    ])
  end
end
