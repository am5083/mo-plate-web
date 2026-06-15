# mo-plate-web

A small Elm frontend for [mo-plate-finder](https://github.com/) built as an excuse to learn Elm.

## Why this exists

I came across a job opening that listed Elm, I'd had some Elixir/Erlang experience + OCaml and figured I'd give it a shot to see whether or not it was appealing. I decided
the best thing to do was a simple webpage frontend to my existing OCaml app.

So this repo is a learning exercise more than anything.

## What it does

Given a seed string, it generates a set of candidate license-plate variations by
running the seed through a handful of transformations:

- **normalize** — uppercase, strip everything that isn't `A–Z` or `0–9`
- **reverse** — the seed backwards
- **truncate** — every left- and right-anchored substring
- **dropAny** — the seed with each single character removed
- **padSimple** — the seed with common suffixes appended (e.g. `MO`, `STL`, `KC`, digits), capped at 7 characters

Results are deduplicated and listed live as you type.

## Project layout

- `src/Main.elm` — the [Elm Architecture](https://guide.elm-lang.org/architecture/) app (model / update / view), wired up as a `Browser.sandbox`
- `src/Variations.elm` — the pure variation-generation logic

## Running it

Requires [Elm 0.19.1](https://guide.elm-lang.org/install/elm.html).

```sh
elm reactor
```

Then open <http://localhost:8000/src/Main.elm>.

Or build a standalone HTML file:

```sh
elm make src/Main.elm --output=index.html
```

# TODO

1. Style the frontend + add API support; style frontend
2. Implement OCaml backend + add docker container + host on gh pages


