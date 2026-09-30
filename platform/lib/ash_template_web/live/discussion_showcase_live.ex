defmodule AshTemplateWeb.DiscussionShowcaseLive do
  @moduledoc """
  How a forum thread looks on a Regent site (`Regent.Discussion`, from Patchbay's
  discussion page), with a sample thread.

  Nothing here is stored: the posts are samples, and a like changes only this
  page until it reloads. The reply filters are links, so each one has its own
  address. The `discussions` skill says how a product stores posts, likes and
  views.
  """
  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.Shell
  alias Regent.Discussion, as: D
  alias Regent.Primitives, as: P

  @filters [{"all", "All replies"}, {"solution", "Solution"}, {"house", "Ash Template replies"}]

  @impl true
  def mount(_params, _session, socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/showcase/discussion"))
     |> assign(
       local?: AshTemplateWeb.Showcase.mode() == :local,
       now: now,
       opening: opening(now),
       all_replies: replies(now),
       liked: MapSet.new(["r2"])
     ), layout: false}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = if params["replies"] in ["solution", "house"], do: params["replies"], else: "all"
    {:noreply, assign(socket, filter: filter)}
  end

  @impl true
  def handle_event("like", %{"post" => id}, socket) do
    liked = socket.assigns.liked

    liked =
      if MapSet.member?(liked, id), do: MapSet.delete(liked, id), else: MapSet.put(liked, id)

    {:noreply, assign(socket, liked: liked)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        shown: Enum.filter(assigns.all_replies, &shown?(&1, assigns.filter)),
        solution: Enum.find(assigns.all_replies, & &1.solution),
        like_total:
          Enum.sum(Enum.map([assigns.opening | assigns.all_replies], &likes(&1, assigns.liked)))
      )

    ~H"""
    <link rel="stylesheet" href="/showcase/style.css" />
    <main id="discussion-page" class="sc onchain-workshop discussion-page">
      <header class="sc-header payments-page-header">
        <a class="sc-wordmark" href="/showcase">Ash <span>Workshop</span></a>
        <span :if={@local?} class="sc-local">Local only</span>
        <Shell.theme_toggle id="discussion-page-theme" />
      </header>

      <section class="onchain-workshop-intro">
        <p class="sc-eyebrow">Example</p>
        <h1>A discussion thread</h1>
        <p>
          This is how a question and its replies read on a Regent site: one column, a picture
          beside each name, the answer that worked quoted under the question, and a heart on
          every post.
        </p>
        <p>
          The posts are samples. Liking one changes only this page, and nothing is kept when it
          reloads.
        </p>
      </section>

      <D.thread
        id="sample-thread"
        title="Why does the sign-in window close before my wallet opens?"
        solved
        replies={length(@all_replies)}
        views={214}
        likes={@like_total}
        last_activity_at={List.last(@all_replies).at}
        last_activity={ago(List.last(@all_replies).at, @now)}
      >
        <:context>
          <span>Asked on Pixel Garden</span><P.status>Question</P.status>
        </:context>
        <.sample_post post={@opening} opening now={@now} liked={@liked}>
          <:solved>
            <D.solved
              id="sample-solved"
              author={@solution.author}
              at={@solution.at}
              date={Calendar.strftime(@solution.at, "%-d %B %Y")}
              href={solution_href(@shown)}
            >
              <p :for={line <- @solution.body}>{line}</p>
            </D.solved>
          </:solved>
        </.sample_post>

        <D.replies
          id="sample-replies"
          count={length(@all_replies)}
          shown={length(@shown)}
          filters={filters(@filter)}
          empty="No replies match this filter."
        >
          <.sample_post :for={reply <- @shown} post={reply} now={@now} liked={@liked} />
        </D.replies>
      </D.thread>
    </main>
    """
  end

  attr :post, :map, required: true
  attr :opening, :boolean, default: false
  attr :now, DateTime, required: true
  attr :liked, :any, required: true
  slot :solved

  defp sample_post(assigns) do
    ~H"""
    <D.post
      id={@post.id}
      opening={@opening}
      author={@post.author}
      at={@post.at}
      ago={ago(@post.at, @now)}
      href={"##{@post.id}"}
      solution={@post.solution}
      house={@post.house}
    >
      <:avatar>
        <span class={["discussion-avatar", @post.house && "discussion-avatar--house"]}>
          {RegentFormat.monogram(@post.author, "?")}
        </span>
      </:avatar>
      <:label :if={@post.house}>
        <D.label>Ash Template</D.label>
      </:label>
      <:label :if={@post.solution}>
        <D.label good>Solution</D.label>
      </:label>
      <p :for={line <- @post.body}>{line}</p>
      <:solved :if={@solved != []}>{render_slot(@solved)}</:solved>
      <:actions>
        <D.like
          count={likes(@post, @liked)}
          liked={MapSet.member?(@liked, @post.id)}
          likers={@post.likers}
          others={@post.others}
          phx-click="like"
          phx-value-post={@post.id}
        />
      </:actions>
    </D.post>
    """
  end

  defp shown?(_reply, "all"), do: true
  defp shown?(reply, "solution"), do: reply.solution
  defp shown?(reply, "house"), do: reply.house

  defp filters(current) do
    for {value, label} <- @filters do
      %{
        label: label,
        href: "/showcase/discussion?replies=#{value}#sample-replies",
        current: value == current
      }
    end
  end

  # The answer itself when it is on screen, otherwise the filter that shows it.
  defp solution_href(shown) do
    if Enum.any?(shown, & &1.solution),
      do: "#r2",
      else: "/showcase/discussion?replies=solution#r2"
  end

  # The sample's own likes, plus the reader's when they like it.
  defp likes(post, liked) do
    length(post.likers) + post.others + if(MapSet.member?(liked, post.id), do: 1, else: 0)
  end

  defp ago(at, now), do: RegentFormat.relative_time(at, now)

  defp opening(now) do
    %{
      id: "post",
      author: "Mara Quill",
      at: DateTime.add(now, -26, :hour),
      solution: false,
      house: false,
      likers: [%{name: "Ode Park", href: nil}, %{name: "Lin Tavers", href: nil}],
      others: 3,
      body: [
        "I press Sign in, the window opens for a moment, then closes before my wallet asks me anything.",
        "It happens in Safari on my phone. On my laptop it works."
      ]
    }
  end

  defp replies(now) do
    [
      %{
        id: "r1",
        author: "Ode Park",
        at: DateTime.add(now, -25, :hour),
        solution: false,
        house: false,
        likers: [],
        others: 0,
        body: ["Same here on an older iPhone. Does it happen in a private tab too?"]
      },
      %{
        id: "r2",
        author: "Ash Template",
        at: DateTime.add(now, -22, :hour),
        solution: true,
        house: true,
        likers: [%{name: "Mara Quill", href: nil}],
        others: 1,
        body: [
          "Safari on a phone blocks a window that opens a moment after you press. Allow pop-ups for the site in Settings, under Safari, then press Sign in again."
        ]
      },
      %{
        id: "r3",
        author: "Mara Quill",
        at: DateTime.add(now, -3, :hour),
        solution: false,
        house: false,
        likers: [],
        others: 0,
        body: ["Allowing pop-ups fixed it. Thank you!"]
      }
    ]
  end
end
