# 🚀 Helpers

> A curated collection of scripts, memos, and code snippets for daily development workflows.

---

## 📂 Contents

| Directory | Purpose | Format |
|-----------|---------|--------|
| **[scripts/](scripts/)** | Reusable scripts and tools | `.sh`, `.py`, or subdirectory with README |
| **[memos/](memos/)** | Command references and cheat sheets | `.md` |
| **[snippets/](snippets/)** | Reusable code templates | Organized by language |

---

## 🛠️ Usage

### Scripts
Scripts can be organized as standalone files or in subdirectories with their own documentation.

```bash
# Run a standalone script
./scripts/<script-name>.sh

# Or navigate to script directory
cd scripts/<script-group>/
./<script-name>.sh  # or .py for Python scripts
```

Each script directory contains a `README.md` with usage details.

### Memos
Quick-reference guides for common commands and workflows.

### Snippets
Reusable code blocks organized by language/framework.

---

## 📥 Adding Content

| Type | Location | Format |
|------|----------|--------|
| Script | `scripts/` | Executable files or subdirectory with README |
| Memo | `memos/` | Markdown files (`.md`) |
| Snippet | `snippets/<language>/` | Code files with descriptive names |

**Best practices:**
- Include a `README.md` for script groups explaining purpose and usage
- Use descriptive, verb-based names for scripts (e.g., `export_variables.sh`)
- Add a header comment with usage examples in scripts
- Keep memos concise and action-oriented

---

## 📊 Current Scripts

| Script Group | Description |
|--------------|-------------|
| [gitlab-manage-project-vars](scripts/gitlab-manage-project-vars/) | Export/import GitLab CI/CD variables |
| [s3-restore](scripts/s3-restore/) | S3 backup restoration utilities |

---

## 🤝 Contributing

1. **Create a feature branch** from `main`
2. **Add your content** following the structure above
3. **Test your scripts** before committing
4. **Use descriptive commit messages**
5. **Open a PR** for review

---

## 📁 Structure

```
helpers/
├── README.md                    # This file
├── scripts/
│   ├── <script-name>.sh         # Standalone scripts
│   └── <script-group>/          # Script collections
│       ├── README.md           # Group documentation
│       ├── *.sh                # Shell scripts
│       └── *.py                # Python scripts
├── memos/
│   └── <topic>.md              # Cheat sheets
└── snippets/
    └── <language>/
        └── <name>.<ext>        # Code snippets
```
