# LiveView content negotiation regression

On 14 October 2026, Autolaunch's `/upcoming-stocks` could select JSON through
`Accept: application/json` or `?_format=json`. LiveView returned safe HTML, which
Jason cannot encode, and the request crashed with a tuple encoding error.

Use Phoenix's `accepts` plug to reject unsupported formats before rendering.
HTML LiveViews must not accept JSON. A JSON controller may have its own format
pipeline while retaining its existing session, CSRF and authorization plugs.
Keep intentional Markdown and JSON document routes working. Do not implement a
Jason encoder for safe HTML or widen an authentication contract to align files.

The invariants: neither way of selecting JSON reaches an HTML LiveView, a browser
still gets HTML, and the existing JSON session fetch still answers. Carry them into
each site, adapting the real routes and existing JSON/Markdown contracts. Preserve
each site's security checks. In Autolaunch, the explicit JSON session requests and
X account-link requests keep their JSON admission.

Template's `/auth/session` currently accepts the browser's wildcard request and
returns JSON; explicit `Accept: application/json` is rejected. This incident
does not change that separate contract.
