# Helpers

A curated collection of reusable scripts, memos, code snippets, and AI resources for daily development workflows.

---

## Contents

| Directory | Purpose |
|-----------|---------|
| **[scripts/](scripts/)** | Executable automation tools. Each group has its own subdirectory and `README.md`. |
| **[ai/](ai/)** | Prompts, skills, and other AI-related resources. |
| **[memos/](memos/)** | Quick-reference guides and cheat sheets. |
| **[snippets/](snippets/)** | Reusable code fragments organized by language. |

## Script groups

| Group | Description |
|-------|-------------|
| [gitlab-vars](scripts/gitlab-vars/) | Export and import GitLab CI/CD variables. |
| [s3-restore](scripts/s3-restore/) | Bulk restore and status checking for archived S3 objects. |

## Usage

Most scripts can be run directly after cloning. Check each group's `README.md` for prerequisites and examples.

```bash
# Example: export GitLab CI/CD variables
cd scripts/gitlab-vars/
./export_variables.sh <group_id> [output_file]
# or
python export_variables.py --group-id <group_id> --output variables.json
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
