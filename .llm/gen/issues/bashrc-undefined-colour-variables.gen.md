# Issue: `.bashrc` references undefined colour variables

## Affected files

- [defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc) — line 1

## Description

The PS1 line in [defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc) reads:

```
PS1="$dim[\t] $teal\u@\h $blue\w$reset: "
```

The variables `$dim`, `$teal`, `$blue` and `$reset` are never defined anywhere in this file (or in any other file under [defaults/dotfiles/](../../../defaults/dotfiles)). When bash sources the file, these expand to empty strings, producing the functional but colourless prompt:

```
[\t] \u@\h \w:
```

This is not a bug — the prompt works — but it suggests the file was extracted from a larger bashrc that defined the colour escapes (e.g. `dim=$'\e[2m'`, `teal=$'\e[36m'`, etc.) and that those definitions were not carried over. Users who copy this file expecting coloured output will see none.

## Suggested fix

Either:

- Define the four colour variables at the top of the `.bashrc` (e.g. `local dim=$'\e[2m' teal=$'\e[36m' blue=$'\e[34m' reset=$'\e[0m'` in a function, or as plain assignments before the PS1 line), or
- Remove the undefined variables from PS1 to make the intent explicit.

## Related

- [Review: current repository review](../reviews/repository-review.gen.md)
