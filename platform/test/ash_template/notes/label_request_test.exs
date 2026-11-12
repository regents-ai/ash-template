defmodule AshTemplate.Notes.LabelRequestTest do
  # Invariant: a note's save never waits on the site's daily-question lock. It
  # only queues the label request, which a job makes once the save has
  # committed, as the person who saved; a note deleted first gets no question;
  # and however many requests run at once, the day's number of questions is
  # never passed.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: AshTemplate.Repo, prefix: "ash_template_app"

  import Ecto.Query
  require Ash.Query

  alias AshTemplate.{Accounts, Notes, Repo}
  alias AshTemplate.Actors.{Human, System}
  alias AshTemplate.Notes.Decision

  setup do
    key = Application.get_env(:regent_jev, :api_key)
    limits = Application.fetch_env!(:ash_template, :note_labels)
    Application.put_env(:regent_jev, :api_key, "test-key")

    on_exit(fn ->
      Application.put_env(:regent_jev, :api_key, key)
      Application.put_env(:ash_template, :note_labels, limits)
    end)

    %{limits: limits}
  end

  describe "one save" do
    setup do
      owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
      %{actor: person()}
    end

    test "queues its label request, which asks as the person once the save has committed",
         %{actor: actor} do
      note = Notes.create_note!(%{title: "Seed list"}, actor: actor)

      assert decisions([note.id]) == []
      assert_enqueued queue: :default, args: %{"listener" => "request_label"}

      assert %{success: 1} = Oban.drain_queue(queue: :default)

      account_id = actor.human_account_id
      assert [%{state: :pending, human_account_id: ^account_id}] = decisions([note.id])
      assert_enqueued queue: :labels
    end

    test "asks nothing for a note deleted before its request runs", %{actor: actor} do
      note = Notes.create_note!(%{title: "Gone soon"}, actor: actor)
      :ok = Notes.destroy_note(note, actor: actor)

      assert %{cancelled: 1} = Oban.drain_queue(queue: :default)
      assert decisions([note.id]) == []
      refute_enqueued queue: :labels
    end
  end

  describe "requests at once" do
    # The race needs separate connections that really commit, so the rows these
    # runs write stay in the test database; every run uses its own people.
    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual) end)
    end

    test "never ask more than the day's number of questions", %{limits: limits} do
      today = DateTime.new!(Date.utc_today(), ~T[00:00:00])
      asked = Decision |> Ash.Query.filter(inserted_at >= ^today) |> Ash.count!(authorize?: false)
      Application.put_env(:ash_template, :note_labels, Keyword.put(limits, :daily_questions, asked + 2))

      note_ids = for _ <- 1..5, do: Notes.create_note!(%{title: "Race"}, actor: person()).id
      on_exit(fn -> cancel_jobs(note_ids) end)
      jobs = label_jobs(note_ids)
      assert length(jobs) == 5

      jobs
      |> Task.async_stream(&AshOban.Signals.Worker.perform(%{&1 | attempt: 1}),
        max_concurrency: 3,
        timeout: 30_000
      )
      |> Enum.each(fn {:ok, result} -> assert result == :ok end)

      assert length(decisions(note_ids)) == 2
    end
  end

  defp label_jobs(note_ids) do
    Repo.all(
      from j in Oban.Job,
        where:
          j.state == "available" and fragment("?->>'listener'", j.args) == "request_label" and
            fragment("?->'payload'->>'note_id'", j.args) in ^note_ids
    )
  end

  # The committed jobs a race leaves, its label requests and the questions they
  # asked, must never run in a later test.
  defp cancel_jobs(note_ids) do
    asked = note_ids |> decisions() |> Enum.map(& &1.id)

    Repo.update_all(
      from(j in Oban.Job,
        where:
          j.state == "available" and
            (fragment("?->'payload'->>'note_id'", j.args) in ^note_ids or
               fragment("?->'primary_key'->>'id'", j.args) in ^asked)
      ),
      set: [state: "cancelled", cancelled_at: DateTime.utc_now()]
    )
  end

  defp decisions(note_ids) do
    Decision
    |> Ash.Query.filter(note_id in ^note_ids)
    |> Ash.read!(authorize?: false)
  end

  defp person do
    wallet = "0x" <> (:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower))
    did = "did:privy:label-request-" <> Ecto.UUID.generate()

    did
    |> Accounts.register_verified!(wallet, [wallet], actor: %System{})
    |> Human.for_account()
  end
end
