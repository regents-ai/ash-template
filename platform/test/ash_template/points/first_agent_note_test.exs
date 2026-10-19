defmodule AshTemplate.Points.FirstAgentNoteTest do
  # Invariant: a one-time award yields exactly one ledger entry per account,
  # however many qualifying events arrive, in whatever order or at once, and an
  # award already earned records nothing more and queues no award. The agent's
  # Points answer names the agent that earned it.
  #
  # The races need separate connections that really commit, so the rows these
  # runs write stay in the test database; every run uses its own person.
  use ExUnit.Case, async: false
  use ExUnitProperties

  import Ecto.Query
  require Ash.Query
  alias AshTemplate.{Accounts, Agents, Notes, Repo}
  alias AshTemplate.Actors.{Agent, System}
  alias RegentPoints.{Entry, Event, IntakeWorker, Store, Worker}

  @rule "template.first_agent_note"

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    starts_at = Application.get_env(:regent_points, :starts_at)
    rules = Application.get_env(:regent_points, :approved_rules)
    Application.put_env(:regent_points, :starts_at, ~U[2020-01-01 00:00:00Z])
    Application.put_env(:regent_points, :approved_rules, [@rule])

    on_exit(fn ->
      Application.put_env(:regent_points, :starts_at, starts_at)
      Application.put_env(:regent_points, :approved_rules, rules)
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end)
  end

  property "a person's agents' notes earn the first-note award once, in one entry" do
    check all(
            notes <- integer(1..5),
            agents <- integer(1..2),
            together? <- boolean(),
            max_runs: 8
          ) do
      person = person()
      names = Enum.map(1..agents, &"Agent #{&1}")
      actors = Enum.map(names, &agent(person, &1))

      if together? do
        # Every note is written first; their checks and awards then run at once.
        ids = for n <- 1..notes, do: note(Enum.at(actors, rem(n, agents)))
        ids |> intake_jobs() |> run_at_once(IntakeWorker)
        person.account.id |> award_jobs() |> run_at_once(Worker)
      else
        # Each note is checked and awarded before the next is written.
        for n <- 1..notes do
          [note(Enum.at(actors, rem(n, agents)))] |> intake_jobs() |> run_at_once(IntakeWorker)
          person.account.id |> award_jobs() |> run_at_once(Worker)
        end
      end

      account_id = person.account.id

      assert [%{points_micro_delta: 10_000_000}] =
               Ash.read!(Ash.Query.filter(Entry, account_id == ^account_id),
                 actor: Store.system()
               )

      assert [%{processing_status: :confirmed}] =
               Ash.read!(Ash.Query.filter(Event, account_id == ^account_id),
                 actor: Store.system()
               )

      {:ok, summary} = RegentPoints.summary(actor: hd(actors))

      assert [%{by: "agent", agent: name, status: :counted}] =
               AshTemplateWeb.PointsEntries.answer(summary).entries

      assert name in names
    end
  end

  defp intake_jobs(note_ids) do
    Repo.all(
      from j in Oban.Job,
        where:
          j.worker == "RegentPoints.IntakeWorker" and j.state == "available" and
            fragment("?->>'source_event_key'", j.args) in ^note_ids
    )
  end

  defp award_jobs(account_id) do
    events =
      Ash.read!(Ash.Query.filter(Event, account_id == ^account_id), actor: Store.system())
      |> Enum.map(& &1.id)

    Repo.all(
      from j in Oban.Job,
        where:
          j.worker == "RegentPoints.Worker" and j.state == "available" and
            fragment("?->>'event_id'", j.args) in ^events
    )
  end

  # Three at once: enough to race on the account's lock within the test pool.
  defp run_at_once(jobs, worker) do
    jobs
    |> Task.async_stream(&worker.perform(%{&1 | attempt: 1}), max_concurrency: 3, timeout: 30_000)
    |> Enum.each(fn {:ok, result} -> assert result == :ok end)

    Repo.update_all(from(j in Oban.Job, where: j.id in ^Enum.map(jobs, & &1.id)),
      set: [state: "completed"]
    )
  end

  defp note(actor) do
    Notes.create_note!(%{title: "Note", operation_id: Ecto.UUID.generate()}, actor: actor).id
  end

  defp person do
    did = "did:privy:first-note-" <> Ecto.UUID.generate()
    wallet = wallet()
    account = Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
    %{did: did, account: account}
  end

  # A paired agent as this site's agent sign-in makes it.
  defp agent(person, name) do
    wallet = wallet()

    code =
      RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: person.did})

    RegentAgents.pair_agent!(code.code, name, :codex,
      actor: %RegentAgents.Agent{wallet: wallet}
    )

    record = Agents.sign_in_agent!(wallet, actor: %System{})
    {:ok, pairing} = RegentAgents.Authority.resolve(Repo, wallet)
    Agent.paired(record, person.account, pairing)
  end

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
