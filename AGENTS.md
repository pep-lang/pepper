# Working in this repository

Conventions that apply to any agent (or person) working here. Tool-specific
workflows live in `.agents/skills/`; this file is for rules that hold
everywhere.

## Pass non-trivial strings to CLI tools through files, never inline

Any string longer than a few plain words — commit messages, PR bodies, review
text, JSON payloads, scripts — goes into a file, and the tool reads the file:

```bash
git commit -F message.txt                       # not -m "$(cat <<'EOF' ...)"
gh pr create --body-file body.md                # not --body "..."
gh api ... --input payload.json                 # not -f body='...'
gh api ... -F body=@body.md
```

Inline heredocs and quoted substitutions look fine and then fail in ways that
are easy to miss:

- **Backticks get evaluated.** A commit message containing `` `gh run watch` ``
  passed through `git commit -m "$(cat <<'EOF' … EOF)"` actually *executed*
  `gh run watch`, whose usage error was spliced into the message and left git
  parsing the remainder as pathspecs. A quoted heredoc delimiter is not
  sufficient protection once another shell layer is involved.
- **Quotes and `$` interpolate or vanish.** Apostrophes, `"`, `$var`, `!`, and
  newlines each have their own failure mode depending on the quoting layer that
  happens to be in play.
- **Truncation is silent.** A mangled argument frequently still produces a
  successful-looking command, so the damage surfaces later — as a wrong commit
  message, a half-written PR body, or a corrupted API payload.

There is no length at which inline becomes "safe enough" to be worth the risk;
writing a file costs one extra step and removes the whole class of failure.
Delete the temporary file afterwards, and keep it out of commits — or write it
somewhere already ignored.

In GitHub Actions, the same rule takes a different form: untrusted or
non-trivial values reach a `run:` body through `env:`, never through `${{ }}`
interpolation, which splices text into the script before bash parses it.
