defmodule AshTemplate.Notes.DecisionOutlivesNoteTest do
  # A label question is paid for and counts against the day's budget, the site's
  # and the writer's. Deleting the note it was about must not take the question
  # with it: saving, waiting for the label and deleting, over and over, would
  # otherwise ask paid questions without end and lose what each one cost.
  use ExUnit.Case, async: false

  require Ash.Query

  alias AshTemplate.{Accounts, Notes}
  alias AshTemplate.Actors.{Human, System}
  alias AshTemplate.Notes.Decision
  alias AshTemplate.Notes.Decision.UnderDailyBudget

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    limits = Application.fetch_env!(:ash_template, :note_labels)
    on_exit(fn -> Application.put_env(:ash_template, :note_labels, limits) end)

    wallet = "0x" <> String.duplicate("8", 40)
    account = Accounts.register_verified!("did:privy:decision-outlives", wallet, [wallet], actor: %System{})
    actor = Human.for_account(account)

    %{actor: actor, person: [actor: actor, context: %{client_key: "decision-outlives"}], limits: limits}
  end

  test "deleting a note keeps its label question, its cost and its place in the day's budget",
       %{actor: actor, person: person, limits: limits} do
    Application.put_env(:ash_template, :note_labels, Keyword.put(limits, :person_daily_questions, 2))

    for title <- ["First", "Second"] do
      note = Notes.create_note!(%{title: title}, person)
      asked(note, actor)
      assert :ok = Notes.destroy_note(note, person)
    end

    kept =
      Decision
      |> Ash.Query.filter(human_account_id == ^actor.human_account_id)
      |> Ash.read!(authorize?: false)

    assert [%{note_id: nil, cost_usd: cost}, %{note_id: nil}] = kept
    assert Decimal.equal?(cost, Decimal.new("0.0004"))

    # Both questions still count, so the person has none left today.
    refute UnderDailyBudget.match?(actor, %{}, [])
  end

  # An answered question about `note`, as the job leaves it.
  defp asked(note, actor) do
    Ash.Seed.seed!(Decision, %{
      note_id: note.id,
      human_account_id: actor.human_account_id,
      question: "Which label fits?",
      choices: ["idea", "task"],
      state: :answered,
      choice: "idea",
      cost_usd: Decimal.new("0.0004")
    })
  end
end
