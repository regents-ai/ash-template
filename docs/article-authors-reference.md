# Article bylines

`Regent.Blog.article` supports an ordered `authors` list. The site validates each
name and HTTPS X profile URL before saving; the shared component renders each
author and their own link.

```elixir
post = Map.merge(post, %{
  authors: [
    %{name: "First Author", x: "https://x.com/first_author"},
    %{name: "Second Author", x: "https://x.com/second_author"}
  ]
})
```

Pass that post to the existing article component along with the site's gallery
path and label. For the gallery's plain-text author field, join the names with
commas. Existing posts without `authors`, or with an empty list, keep the legacy
`author` and `author_x` byline.

Reference implementation: Regents `RegentsWeb.Blog.present/1`; canonical shared
contract: design-system `BLOG.md`. Content storage and staff authorization belong
to the host site. The shared component does not grant access or save content.
