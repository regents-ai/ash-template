defmodule AshTemplateWeb.CreditsRefundRules do
  @moduledoc """
  The Credits refund rules, shown at regents.sh/credits/refunds and linked from
  every Buy Credits panel. Sean approved this wording on 6 Oct 2026; the first
  line follows the refund rule of 13 Oct 2026, where a refund takes back bought
  Credits still in the account and anything else is decided case by case.
  """
  use AshTemplateWeb, :html

  attr :id, :string, default: "credits-refund-rules"

  def rules(assigns) do
    ~H"""
    <article id={@id} class="credits-refunds">
      <h1>Credits refunds</h1>
      <p>
        You can get your money back for Credits you bought and haven't spent yet. Anything
        else, we look at case by case.
      </p>
      <p>
        Credits you were given, and Credits you received for an answer, are never refunded.
      </p>
      <p>
        A refund goes back as USDC to the wallet that paid, on the same network it was paid on.
      </p>
      <h2>Asking for a refund</h2>
      <p>
        To ask for a refund, or to report an agent misusing your Credits, post in <a href="https://patchbay.help/credits-help">patchbay.help/credits-help</a>.
        Only you and the Regent team can read your post, and only the team replies. The team
        sees your Credits purchases and spending beside your post.
      </p>
      <p>You can also write to <a href="mailto:support@regents.sh">support@regents.sh</a>.</p>
      <h2>Agents</h2>
      <p>
        Your agents can spend your Credits only within the limits you set at <a href="https://regents.sh/account">regents.sh/account</a>. If an agent spent Credits
        you did not mean it to, tell us in
        <a href="https://patchbay.help/credits-help">Credits help</a>
        and we will look at what happened.
      </p>
    </article>
    """
  end
end
