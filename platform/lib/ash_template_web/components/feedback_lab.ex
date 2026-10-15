defmodule AshTemplateWeb.FeedbackLab do
  @moduledoc "Local motion studies. Candidate treatments, never shared defaults."
  use AshTemplateWeb, :html
  alias Regent.Primitives, as: P

  attr :name, :string, required: true
  attr :validity, :string, required: true
  attr :receipt, :integer, required: true
  attr :state, :string, required: true
  attr :messages, :list, required: true

  def content(assigns) do
    ~H"""
    <section
      id="feedback-lab"
      class="flair"
      phx-hook="LabFeedback"
      data-validity={@validity}
      data-receipt={@receipt}
      data-state={@state}
    >
      <header class="flair-intro">
        <p class="motion-lab__kicker">Study 01 / Considered feedback</p>
        <h2>A little life. At the right moment.</h2>
        <p>
          Touch, confirm, compose. Six studies in useful detail. These are local demos; nothing is saved or sent outside this page.
        </p>
        <span class="flair-tag">Candidate · not a site default</span>
      </header>

      <div class="flair-grid">
        <article class="flair-study" aria-labelledby="flair-touch-title">
          <header>
            <span class="flair-index">01 / Touch</span><h3 id="flair-touch-title">
              An invitation, then an answer.
            </h3>
          </header>
          <p>
            A fine edge appears on hover. Press and hold: the label gives slightly, while the target stays put.
          </p>
          <div class="flair-touch">
            <P.button variant="secondary" class="flair-button" data-press="flair" data-flair-press>
              <span data-flair-label>Try a press <span class="flair-arrow" aria-hidden="true">↗</span></span>
            </P.button>
            <a href="#flair-material-title" class="flair-link">Explore the materials
            <span aria-hidden="true">→</span></a>
          </div>
          <p class="flair-spec">140ms down / 105ms up · 0.98 scale · stable hit area</p>
        </article>

        <article class="flair-study" aria-labelledby="flair-form-title">
          <header>
            <span class="flair-index">02 / Confirm</span><h3 id="flair-form-title">
              Confidence without confetti.
            </h3>
          </header>
          <.form
            for={%{}}
            as={:demo}
            id="flair-form"
            phx-change="flair_validate"
            phx-submit="flair_submit"
          >
            <label for="flair-name">Project name</label>
            <div class="flair-field" data-state={@validity}>
              <input
                id="flair-name"
                name="demo[name]"
                value={@name}
                maxlength="40"
                autocomplete="off"
                placeholder="e.g. Field notes"
                aria-describedby="flair-name-hint"
                aria-invalid={to_string(@validity == "invalid")}
              />
              <span class="flair-valid-mark" data-valid-mark aria-hidden="true">✓</span>
            </div>
            <p id="flair-name-hint" class="flair-hint" aria-live="polite">
              <%= case @validity do %>
                <% "valid" -> %>
                  Looks good. Ready to submit.
                <% "invalid" -> %>
                  Use 3–40 characters, excluding surrounding spaces.
                <% _ -> %>
                  Use 3–40 characters. Validation stays beside the field.
              <% end %>
            </p>
            <P.button variant="secondary" data-press="flair" data-flair-press type="submit">
              <span data-flair-label>Confirm demo</span>
            </P.button>
          </.form>
          <p class="flair-receipt" role="status" data-receipt-mark>
            <%= if @receipt > 0 do %>
              <span aria-hidden="true">✓</span> Demo confirmed · {@receipt}
            <% else %>
              Your confirmation will appear here.
            <% end %>
          </p>
          <p class="flair-spec">Validity: quiet edge · confirmation: one 200ms response</p>
        </article>

        <article class="flair-study flair-study--chat" aria-labelledby="flair-chat-title">
          <header>
            <span class="flair-index">03 / Compose</span><h3 id="flair-chat-title">
              Room for the words.
            </h3>
          </header>
          <p>
            The draft indicator answers the first keystroke. The text and caret never move for effect.
          </p>
          <ol class="flair-transcript" aria-label="Local demo messages" aria-live="polite">
            <li :if={@messages == []} class="flair-chat-empty">Your preview messages appear here.</li>
            <li :for={message <- @messages}>
              <span class="flair-message-label">You · local preview</span><p>{message}</p>
            </li>
          </ol>
          <.form for={%{}} as={:chat} id="flair-chat-form" phx-submit="flair_chat">
            <label for="flair-message">Message</label>
            <textarea
              id="flair-message"
              name="chat[message]"
              rows="2"
              maxlength="280"
              placeholder="Write a thought…"
              required
            ></textarea>
            <div class="flair-compose-footer">
              <span class="flair-typing" data-typing><span aria-hidden="true">●</span>
              <span data-typing-label>Ready when you are</span></span>
              <P.button variant="secondary" type="submit" data-press="flair" data-flair-press><span data-flair-label>Preview message
              <span aria-hidden="true">↑</span></span></P.button>
            </div>
          </.form>
          <p class="flair-spec">First-input state cue · no per-character animation</p>
        </article>
      </div>

      <article class="flair-material" aria-labelledby="flair-material-title">
        <header class="flair-material-head">
          <div>
            <span class="flair-index">04 / Material & state</span><h3 id="flair-material-title">
              A border with something to say.
            </h3>
          </div>
          <p>Gradient light lives at the edge. The content stays opaque, readable, and still.</p>
        </header>
        <div class="flair-states" role="group" aria-label="Material state">
          <P.button
            :for={
              {state, label} <- [
                {"ready", "Ready"},
                {"working", "Working"},
                {"confirmed", "Confirmed"},
                {"attention", "Needs attention"}
              ]
            }
            variant="secondary"
            phx-click="flair_state"
            phx-value-state={state}
            aria-pressed={to_string(@state == state)}
            data-press="flair"
          >{label}</P.button>
        </div>
        <div class="flair-material-grid">
          <div
            id="flair-gradient-island"
            class="flair-gradient-island"
            phx-mounted={Phoenix.LiveView.JS.ignore_attributes("data-gradient-ready")}
            data-state={@state}
            phx-hook="LabGradient"
            phx-update="ignore"
            aria-hidden="true"
          >
            <div class="flair-gradient-still"></div><canvas data-gradient-canvas></canvas>
            <span class="flair-material-caption">Color / light / state</span>
          </div>
          <div class="flair-edge-card" data-state={@state}>
            <span class="flair-edge-skin" aria-hidden="true"></span>
            <div class="flair-edge-content">
              <span class="flair-index">Edge light</span><h4>Release checklist</h4>
              <p>Useful detail at the perimeter. No moving light behind the words.</p>
              <p class="flair-state-label" role="status">
                <span aria-hidden="true">{state_icon(@state)}</span> {state_label(@state)}
              </p>
            </div>
          </div>
          <div class="flair-edge-card flair-edge-card--rail" data-state={@state}>
            <span class="flair-edge-skin" aria-hidden="true"></span>
            <div class="flair-edge-content">
              <span class="flair-index">Signal rail</span><h4>Review queue</h4>
              <p>A smaller accent for denser screens. State always has a written label.</p>
              <p class="flair-state-label">
                <span aria-hidden="true">{state_icon(@state)}</span> {state_label(@state)}
              </p>
            </div>
          </div>
        </div>
        <p class="flair-spec">
          VGPU material study + CSS edge treatments · no idle loop ·
          <a href="https://vgpu.sh/examples/gradient" target="_blank" rel="noreferrer">Gradient reference ↗</a>
        </p>
      </article>
      <footer class="flair-notes">
        <strong>Quiet by design.</strong>
        Keyboard actions settle immediately. Less motion keeps state legible without movement. Touch does not inherit hover effects. No animation delays an action.
      </footer>
    </section>
    """
  end

  defp state_icon("ready"), do: "○"
  defp state_icon("working"), do: "◷"
  defp state_icon("confirmed"), do: "✓"
  defp state_icon("attention"), do: "!"
  defp state_label("ready"), do: "Ready for review"
  defp state_label("working"), do: "Review in progress"
  defp state_label("confirmed"), do: "Review confirmed"
  defp state_label("attention"), do: "Needs your attention"
end
