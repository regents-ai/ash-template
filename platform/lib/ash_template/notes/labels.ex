defmodule AshTemplate.Notes.Labels do
  @moduledoc """
  The labels Jev picks from for a note, and the settings it is asked with.

  Jev is asked only while the server has an OpenRouter key
  (`OPENROUTER_API_KEY`); with none, saving a note asks nothing. The model and
  the site's daily number of questions are set in `config/config.exs` under
  `:note_labels`.
  """

  @choices %{
    "idea" => "Something to try, explore or think about later.",
    "task" => "Something the writer needs to do.",
    "question" => "Something the writer wants answered or is unsure about.",
    "reference" => "Facts, links or details kept to look up later.",
    "other" => "None of the above."
  }

  @instructions "Which label fits this note best?"

  @doc "Whether the server can ask Jev."
  @spec asking?() :: boolean()
  def asking?, do: Application.get_env(:regent_jev, :api_key) not in [nil, ""]

  @doc "What Jev is asked about every note."
  @spec instructions() :: String.t()
  def instructions, do: @instructions

  @doc "The question every note is asked, keyed by the name its answer comes back under."
  @spec questions() :: %{String.t() => RegentJev.question()}
  def questions, do: %{"label" => %{instructions: @instructions, choices: @choices}}

  @doc "The label keys, in a fixed order."
  @spec keys() :: [String.t()]
  def keys, do: @choices |> Map.keys() |> Enum.sort()

  @doc "The model Jev is asked with."
  @spec model() :: String.t()
  def model, do: Keyword.fetch!(settings(), :model)

  @doc "How many questions the whole site may ask Jev each day (UTC)."
  @spec daily_questions() :: pos_integer()
  def daily_questions, do: Keyword.fetch!(settings(), :daily_questions)

  defp settings, do: Application.fetch_env!(:ash_template, :note_labels)
end
