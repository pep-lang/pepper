<!-- Generated from runtime/cli/completions.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Completions

Shell completion scripts generated from a `Parser`: `Shell` names the
shells, and `Parser.completions` writes the script.

Source: `runtime/cli/completions.pep`

## Shell

```pepper
enum Shell
```

A shell that `Parser.completions` writes a completion script for.

### Cases

#### Bash

```pepper
Bash
```

GNU Bash: source the script, or put it in
`~/.local/share/bash-completion/completions/NAME`.

#### Zsh

```pepper
Zsh
```

Zsh: put the script in a directory on `$fpath` as `_NAME`.

#### Fish

```pepper
Fish
```

fish: put the script in `~/.config/fish/completions/NAME.fish`.

#### Powershell

```pepper
Powershell
```

PowerShell (`powershell` on a command line): dot-source the script from your profile.
