# GitLab CI/CD Variables Copy

Scripts to export and import CI/CD variables between GitLab groups via the GitLab REST API.
Available in both **Bash** and **Python**.

## Contents

- **[export_variables.sh](#exportsh--exportpy)** — Export CI/CD variables from a GitLab group to a JSON file (Bash)
- **[import_variables.sh](#importsh--importpy)** — Import CI/CD variables into a GitLab group from a JSON file (Bash)
- **[export_variables.py](#exportsh--exportpy)** — Export CI/CD variables from a GitLab group to a JSON file (Python)
- **[import_variables.py](#importsh--importpy)** — Import CI/CD variables into a GitLab group from a JSON file (Python)

## Usage

### 1. Set Environment Variables

```bash
export GITLAB_URL="https://gitlab.com"       # defaults to https://gitlab.com if not set
export GITLAB_TOKEN="glpat-xxxxxxxxxxxxxxxxxxxx"
```

### 2. Export Variables

#### export.sh / export.py

```bash
# Bash
chmod +x export_variables.sh
./export_variables.sh <source_group_id> [output_file]

# Example
./export_variables.sh 123 variables.json

# Python
python export_variables.py --group-id 123 --output variables.json

# Python with explicit URL and token
python export_variables.py --group-id 123 --output variables.json \
  --url https://gitlab.company.com \
  --token glpat-xxxxxxxxxxxxxxxxxxxx
```

### 3. Import Variables

#### import.sh / import.py

```bash
# Bash — skip existing variables (default)
./import_variables.sh <target_group_id> [input_file] [skip|overwrite]
./import_variables.sh 456 variables.json skip

# Bash — overwrite existing variables
./import_variables.sh 456 variables.json overwrite

# Python — dry run (no changes applied)
python import_variables.py --group-id 456 --input variables.json --dry-run

# Python — skip existing (default)
python import_variables.py --group-id 456 --input variables.json --mode skip

# Python — overwrite existing
python import_variables.py --group-id 456 --input variables.json --mode overwrite
```

## Configuration

Both scripts read configuration from environment variables:

| Variable | Default | Description |
|---|---|---|
| `GITLAB_URL` | `https://gitlab.com` | Base URL of your GitLab instance |
| `GITLAB_TOKEN` | *(required)* | Personal Access Token or Group Token with `api` scope |

The import mode controls conflict resolution:

| Mode | Behavior |
|---|---|
| `skip` | Leaves existing variables untouched (default) |
| `overwrite` | Updates existing variables with values from the file |

> **Important:** Keep `GITLAB_URL` consistent between export and import runs.

## Prerequisites

### Bash

- `bash` 4+
- `curl`
- [`jq`](https://jqlang.github.io/jq/) — JSON processor
  ```bash
  # Install jq
  apt install jq        # Debian / Ubuntu
  yum install jq        # RHEL / CentOS
  brew install jq       # macOS
  ```

### Python

- Python 3.7+
- `requests` library:
  ```bash
  pip install requests
  ```

### GitLab permissions

- Minimum **Maintainer** role in both the source and target groups
- Token scope: `api`

## How It Works

### export_variables.sh / export_variables.py

1. Validates required inputs (token, group ID)
2. Fetches all variables from the source group using the GitLab API with pagination (100 per page)
3. Saves the full variable list to a JSON file
4. Prints a summary table with key, type, protection, mask, and environment scope
5. Warns about variables with empty values (masked variables may not return their value via the API)

### import_variables.sh / import_variables.py

1. Validates required inputs and checks that the input file exists
2. Reads variables from the JSON file
3. Skips variables with empty values (typically masked variables exported without their value)
4. For each variable, attempts to create it via `POST /api/v4/groups/:id/variables`:
   - **201** → created successfully
   - **409** → already exists; applies `skip` or `overwrite` mode
5. In `overwrite` mode, sends a `PUT` request to update the existing variable (scoped by `environment_scope`)
6. Prints per-variable status and a final summary: created, updated, skipped, errors

## JSON File Format

The `variables.json` file produced by the export scripts follows the GitLab API response schema:

```json
[
  {
    "key": "DATABASE_URL",
    "value": "postgres://user:pass@host/db",
    "variable_type": "env_var",
    "protected": true,
    "masked": false,
    "raw": false,
    "environment_scope": "*"
  },
  {
    "key": "DEPLOY_KEY",
    "value": "",
    "variable_type": "env_var",
    "protected": true,
    "masked": true,
    "raw": false,
    "environment_scope": "production"
  }
]
```

> **Security:** `variables.json` may contain sensitive secrets. Do **not** commit it to version control. Add it to `.gitignore`:
> ```
> variables.json
> ```

## Output Examples

### export_variables.sh / export_variables.py

```
🔄 Exporting variables from group ID=123
   URL: https://gitlab.com
   File: variables.json

✅ Exported variables: 42

📋 Variable list:
   - DATABASE_URL [env_var] protected=true masked=false scope=*
   - DEPLOY_KEY [env_var] protected=true masked=true scope=production
   - API_TOKEN [env_var] protected=false masked=true scope=*

⚠️  Note: masked variables may have empty values (GitLab API limitation)
```

### import_variables.sh / import_variables.py

```
🔄 Importing variables into group ID=456
   URL: https://gitlab.com
   File: variables.json
   Variables: 42
   Mode: overwrite

✅ DATABASE_URL — created
🔄 API_TOKEN — updated
⏭️  DEBUG_MODE — already exists, skipping
⚠️  DEPLOY_KEY — empty value (possibly masked), skipping

=============================================
📊 Results:
   Created:   30
   Updated:   8
   Skipped:   4
   Errors:    0
=============================================
```

## Typical Workflow

```bash
# Step 1: Export variables from the source group
./export_variables.sh 123 variables.json
# or
python export_variables.py --group-id 123 --output variables.json

# Step 2: Review the exported file
cat variables.json

# Step 3: Dry-run the import to preview what will happen (Python only)
python import_variables.py --group-id 456 --input variables.json --dry-run

# Step 4: Import into the target group
./import_variables.sh 456 variables.json skip
# or
python import_variables.py --group-id 456 --input variables.json --mode skip

# Step 5: Delete the JSON file when done
rm variables.json
```

## Notes

| Topic | Detail |
|---|---|
| **Token** | Personal Access Token or Group Token with `api` scope required |
| **Role** | Maintainer (or higher) in both source and target groups |
| **Masked variables** | GitLab < 16.x may return empty values for masked variables via the API; these are skipped during import |
| **Environment scope** | Scoped variables (`environment_scope != *`) require GitLab Premium or Ultimate |
| **Self-managed** | Set `GITLAB_URL` to your instance URL (e.g. `https://gitlab.company.com`) |
