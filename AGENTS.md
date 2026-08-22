## Files

The roles of various files are described below, though they might not all exist.

### Conventions

All paths are specified relative to project root.

*Core files* refers to files in this repository excluding all subpaths of files and folders matched by:

- `.coreignore`
- `.gitignore`

### Excluded files

Only edit markdown documents with extension `.gen.md` unless explicitly instructed.

Do not modify:

- `.llm/user/prompts/**`
- `.llm/ref/**`

Only read `.dotfiles/` when instructed to do so.

### Specifications

The files `SPEC.md` and `SPEC.gen.md` are used jointly to provide key project specifications.

### Map

The file `MAP.gen.md` provides a map of implemented core files. Use this file as needed to navigate the repository.

Each file in `MAP.gen.md` should include:

- a link to the file
- a description of the file in 1-2 sentences

### Documents

Documents should be composed in Pandoc markdown and given extension `.gen.md`. Save these in `.llm/gen/docs/` by default.

When referring to a file from within a markdown document, use markdown-formatted links relative to the project root such as:

`[Document title](.llm/gen/docs/document-title.gen.md)`

Documents should capture key information and otherwise be kept as concise as possible.

## Implementation

When editing code, prioritize approaches which are simple, concise and interpretable. Prefer minimal, targeted changes over large refactors. Prefer a modular structure where conceptually distinct aspects are separated into individual files, each with a clear responsibility.

Do not include comments in code.

After implementing a core file, add it to `MAP.gen.md`.

Whenever dependencies are required for the implemention or development tooling, install them.
