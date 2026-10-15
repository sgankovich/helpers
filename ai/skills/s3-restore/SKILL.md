---
name: s3-restore
description: Use when the user needs to restore S3 objects from Glacier, Deep Archive or Intelligent-Tiering archive tiers, check restore status, or verify S3 prefixes/paths exist, especially given a list of S3 paths, folders or run directories.
---

# S3 Restore

## Overview

The GitHub repo `git@github.com:sgankovich/helpers.git` is the single source of truth for restore and check scripts. Never write restore logic from scratch: pull the scripts from the repo and only change the configuration block.

## Workflow

1. **Get the repo.** Clone into the working directory as `helpers/` (or `git -C helpers pull` if present). Run `git fetch` and check `origin/main` first. Scripts live in `scripts/s3-restore/` (`restore.py`, `check.py`, `README.md`). If that path is missing, search all remote branches (`git ls-tree -r --name-only origin/<branch>`) and tell the user where you found them. Do not guess.
2. **Read `scripts/s3-restore/README.md`** for current usage; it overrides this skill if they differ.
3. **Normalize the input list** to full `s3://bucket/prefix/` URIs, one per line, with duplicates removed (`paths.txt`). Cut run-level paths to the folder the user specifies. Ask if the target level is unclear.
4. **Copy `restore.py` and `check.py`** to the working directory (leave `helpers/` untouched). Edit ONLY the CONFIGURATION block in both files:
   - `BUCKET`: bucket name without `s3://`
   - `PREFIXES`: keys after the bucket, trailing `/`, identical in both files
   - Keep `TIER`/`DAYS`/`WORKERS` defaults unless the user asks; state them in your summary.
5. **Set up Python:** `python3 -m venv .venv && .venv/bin/pip install boto3`. A `ModuleNotFoundError: boto3` means this step was skipped.
6. **Verify:** `python3 -m py_compile` both files. Do NOT run `restore.py` (real mode) yourself; it starts billable restores. Give the user the commands.

## Commands for the user

```bash
.venv/bin/python restore.py --dry-run   # preview, no changes
.venv/bin/python restore.py             # start restore (billable)
.venv/bin/python check.py               # re-run every few hours until all "available"
```

## Optional existence check

To verify prefixes contain objects, use `aws s3api list-objects-v2 --bucket B --prefix P --max-keys 1 --no-paginate --query 'length(Contents || `[]`)' --output text`. Do not use `--max-items`: it paginates and prints several numbers.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Rewriting restore/check logic | Copy from the repo, change config only |
| `BUCKET`/`PREFIXES` differ between files | Generate both from the same `paths.txt` |
| Prefix includes `s3://bucket/` | Strip it; keys only |
| Running real restore without user consent | Hand over commands; dry-run first |
| Repo path not found | Check remote branches, then ask the user |
