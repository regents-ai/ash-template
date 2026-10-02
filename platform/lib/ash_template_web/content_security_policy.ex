defmodule AshTemplateWeb.ContentSecurityPolicy do
  @moduledoc """
  The content security policies the site's pages are served under. `reading/0` is
  the strict baseline: everything comes from this site, no page frames another site
  or is framed itself, and forms submit only here. `sign_in/0` adds exactly what
  Privy's wallet sign-in loads, from Privy's published policy and the bundled Privy
  and WalletConnect code; Privy's sign-in window writes its own style elements, so
  only that profile allows them. `showcase/0` is `sign_in/0` for the showcase
  catalog, which frames its own preview page. A site that loads anything else adds
  each origin to the one directive and the one profile that needs it; the only
  wildcard is Privy's own `*.rpc.privy.systems`, from its published policy.
  """

  # The development code reloader runs in a frame from this site.
  @own_frames if Application.compile_env(:ash_template, [AshTemplateWeb.Endpoint, :code_reloader]),
                 do: ["'self'"],
                 else: []

  @baseline [
    {"default-src", ["'none'"]},
    {"script-src", ["'self'"]},
    {"style-src", ["'self'"]},
    # Style attributes only, never style elements: the shared ratio card sizes
    # its fill with one, and an element moving under `JS.ignore_attributes(["style"])`
    # keeps the one Anime.js wrote. Rising words clip by class (`.split-clip`).
    {"style-src-attr", ["'unsafe-inline'"]},
    {"img-src", ["'self'", "data:"]},
    {"font-src", ["'self'"]},
    {"connect-src", ["'self'"]},
    {"frame-src", @own_frames},
    {"base-uri", ["'none'"]},
    {"form-action", ["'self'"]},
    {"frame-ancestors", ["'none'"]}
  ]

  @sign_in %{
    "script-src" => ["https://challenges.cloudflare.com"],
    "style-src" => ["'unsafe-inline'"],
    "img-src" => ["blob:", "https://explorer-api.walletconnect.com"],
    "frame-src" => [
      "https://auth.privy.io",
      "https://verify.walletconnect.com",
      "https://verify.walletconnect.org",
      "https://challenges.cloudflare.com"
    ],
    "connect-src" => [
      "https://auth.privy.io",
      "https://*.rpc.privy.systems",
      "wss://relay.walletconnect.com",
      "wss://relay.walletconnect.org",
      "https://verify.walletconnect.org",
      "https://explorer-api.walletconnect.com",
      "https://rpc.walletconnect.org",
      "https://pulse.walletconnect.org",
      "wss://www.walletlink.org"
    ]
  }

  @doc "The strict baseline, for pages that never start sign-in."
  def reading, do: render(@baseline)

  @doc "The baseline plus Privy wallet sign-in, for pages that can sign someone in."
  def sign_in, do: @baseline |> add(@sign_in) |> render()

  @doc "Sign-in plus framing its own pages, for the showcase catalog's preview."
  def showcase do
    @baseline
    |> add(@sign_in)
    |> add(%{"frame-src" => ["'self'"]})
    |> List.keyreplace("frame-ancestors", 0, {"frame-ancestors", ["'self'"]})
    |> render()
  end

  defp add(directives, additions) do
    for {directive, sources} <- directives,
        do: {directive, Enum.uniq(sources ++ Map.get(additions, directive, []))}
  end

  defp render(directives) do
    directives
    |> Enum.reject(fn {_directive, sources} -> sources == [] end)
    |> Enum.map_join("; ", fn {directive, sources} -> Enum.join([directive | sources], " ") end)
  end
end
