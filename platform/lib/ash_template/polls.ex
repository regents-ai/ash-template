defmodule AshTemplate.Polls do
  @moduledoc """
  Polls: a question with two to ten choices that people vote on for a few
  minutes. Anyone reads them; a signed-in person, or an agent they paired
  acting for them, starts one (`AshTemplate.Polls.Poll`) and votes once in each
  (`AshTemplate.Polls.Vote`).

  The rules, as Keyfleet's polls have them, for people instead of Keys:

  1. **A poll is open for the 1 to 60 minutes its starter chose,** or until
     the starter ends it. It is never removed.
  2. **One vote per person.** Sending the same choice again answers the vote
     already there; a different choice is refused. Votes are never changed.
  3. **Nobody sees which way it leans until it closes.** While it is open only
     the number of votes shows; after, each choice's count. Nobody sees who
     voted for what, and each person sees their own vote.
  4. **A person starts a few a day at most** (`:poll` in `AshTemplate.Limits`).

  Everything an agent does with polls is also a hosted agent tool (`tools`).
  """

  use Ash.Domain, otp_app: :ash_template, extensions: [AshAi, AshPhoenix]

  resources do
    resource AshTemplate.Polls.Poll do
      define :list_polls, action: :list
      define :get_poll, action: :one, args: [:id], not_found_error?: false
      define :start_poll, action: :start
      define :end_poll, action: :end
      define :polls_list, action: :polls_list
      define :polls_show, action: :polls_show, args: [:poll]
      define :polls_start, action: :polls_start
      define :polls_end, action: :polls_end, args: [:poll]
    end

    resource AshTemplate.Polls.Vote do
      define :vote, action: :cast, args: [:poll_id]
      define :polls_vote, action: :polls_vote, args: [:poll]
    end
  end

  # The hosted agent tools: each runs the same action as its HTTP route, its
  # browser tool and its regents-cli command, and is named after them
  # (`AshTemplateWeb.Capabilities` checks both).
  tools do
    tool :polls_list, AshTemplate.Polls.Poll, :polls_list do
      description AshTemplate.Descriptions.hosted(:polls_list)
    end

    tool :polls_show, AshTemplate.Polls.Poll, :polls_show do
      description AshTemplate.Descriptions.hosted(:polls_show)
    end

    tool :polls_start, AshTemplate.Polls.Poll, :polls_start do
      description AshTemplate.Descriptions.hosted(:polls_start)
    end

    tool :polls_vote, AshTemplate.Polls.Vote, :polls_vote do
      description AshTemplate.Descriptions.hosted(:polls_vote)
    end

    tool :polls_end, AshTemplate.Polls.Poll, :polls_end do
      description AshTemplate.Descriptions.hosted(:polls_end)
    end
  end

  @doc """
  The topic every start, vote and end is published on, after it commits:
  `%{event: "start" | "cast" | "end", payload: %{poll_id: id}}`.
  """
  def topic, do: "public:polls"

  @doc "Whether a poll still takes votes at `now`."
  def open?(poll, now \\ DateTime.utc_now()),
    do: is_nil(poll.ended_at) and DateTime.compare(poll.closes_at, now) == :gt
end
