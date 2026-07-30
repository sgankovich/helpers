# Contributing

Thanks for helping improve this helpers collection.

## Repository layout

- `scripts/` — executable automation tools; each group lives in its own subdirectory with a `README.md`.
- `ai/` — AI prompts, skills, and agent resources.
- `memos/` — concise command references and cheat sheets.
- `snippets/` — reusable code fragments organized by language.

## Adding content

1. Create a feature branch from `main`.
2. Add your files in the appropriate directory.
3. Update the relevant `README.md` if you add a new group or language.
4. Keep scripts focused, well-documented, and free of secrets.
5. Open a PR with a clear description of the change.

## Conventions

- Use lowercase names with hyphens for directories and files (e.g., `s3-restore`, `export_variables.py`).
- Include a `README.md` for every script group.
- Do not commit credentials, tokens, or generated output files (`variables.json`, `.env`, etc.).
