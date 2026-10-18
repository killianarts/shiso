# Shiso

## Writing style

These rules apply to Shiso's prose: `docs/`, `org/`, READMEs, docstrings
and `CHANGELOG.org`.

- Follow the Google developer documentation style guide: address the
  reader as "you", use the active voice and the present tense, and put
  the point first.
- Keep sentences to 25 words or fewer, with one idea per sentence.
- Write complete sentences in prose. List items may be fragments, if
  every item in the list is.
- Use plain, precise words. Avoid "simply", "just", "easily" and
  "obviously".
- Write instructions in the imperative, one step per sentence.
- Be welcoming to newcomers to Lisp. Never criticize other projects or
  their documentation.

## Changelog

`CHANGELOG.org` follows Keep a Changelog. Each release opens with a
summary, then the Added, Fixed, Upgrading, Changed and Removed sections.

- The summary starts with one sentence saying what the release is for.
- Then come highlights: one bullet per area, named in bold.
- Each highlight is one or two sentences. It says what the reader gains
  and why, not what the code does.
- Each highlight names one piece of API that shows the benefit, such as
  `shiso:configure` for settings.
- Detail belongs in the sections after the summary, not in it.
- Upgrading lists numbered steps for changes that need the reader to
  act.
- Before writing a highlight, confirm the intended value with the
  maintainer if it isn't clear from the code or its history.
