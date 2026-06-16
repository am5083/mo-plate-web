# Vendored core

`form_parser.ml`, `session.ml`, `plate_check.ml` (and their `.mli`s) are copied
verbatim from the **mo-plate-finder** CLI project. They implement the five-stage
Missouri DOR availability flow (ASP.NET viewstate handling, Imperva cookie
juggling, manual POST-preserving redirects).

They are vendored rather than depended on so this repo clones and builds on its
own. The candidate **generator** is *not* vendored — it lives natively in Elm
(`web/src/Variations.elm`), so generation runs client-side with no backend.

If you change the scraping flow, change it in the CLI repo first, then re-copy.
