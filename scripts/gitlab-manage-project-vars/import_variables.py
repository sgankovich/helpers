#!/usr/bin/env python3
"""
Import CI/CD variables into a GitLab group from a JSON file.

Usage:
    export GITLAB_TOKEN=your_private_token
    python import_variables.py --group-id 456 --input variables.json
    python import_variables.py --group-id 456 --input variables.json --mode overwrite
    python import_variables.py --group-id 456 --input variables.json --dry-run
"""

import argparse
import json
import os
import sys
from dataclasses import dataclass, field

import requests


@dataclass
class Stats:
    created: int = 0
    updated: int = 0
    skipped: int = 0
    errors: int = 0
    details: list = field(default_factory=list)


def create_variable(gitlab_url: str, token: str, group_id: int, var: dict) -> tuple:
    """Create a variable. Returns (status_code, response_text)."""
    headers = {"PRIVATE-TOKEN": token}
    payload = {
        "key": var["key"],
        "value": var.get("value", ""),
        "variable_type": var.get("variable_type", "env_var"),
        "protected": var.get("protected", False),
        "masked": var.get("masked", False),
        "raw": var.get("raw", False),
        "environment_scope": var.get("environment_scope", "*"),
    }

    response = requests.post(
        f"{gitlab_url}/api/v4/groups/{group_id}/variables",
        headers=headers,
        json=payload,
    )
    return response.status_code, response.text


def update_variable(gitlab_url: str, token: str, group_id: int, var: dict) -> tuple:
    """Update an existing variable. Returns (status_code, response_text)."""
    headers = {"PRIVATE-TOKEN": token}
    env_scope = var.get("environment_scope", "*")
    payload = {
        "value": var.get("value", ""),
        "variable_type": var.get("variable_type", "env_var"),
        "protected": var.get("protected", False),
        "masked": var.get("masked", False),
        "raw": var.get("raw", False),
        "environment_scope": env_scope,
    }

    response = requests.put(
        f"{gitlab_url}/api/v4/groups/{group_id}/variables/{var['key']}",
        headers=headers,
        json=payload,
        params={"filter[environment_scope]": env_scope},
    )
    return response.status_code, response.text


def import_variables(
    gitlab_url: str,
    token: str,
    group_id: int,
    variables: list,
    mode: str = "skip",
    dry_run: bool = False,
) -> Stats:
    """Import variables into the target group."""
    stats = Stats()

    for var in variables:
        key = var.get("key", "UNKNOWN")
        value = var.get("value", "")

        # Skip variables without a value
        if not value:
            print(f"⚠️  {key} — empty value, skipping")
            stats.skipped += 1
            continue

        if dry_run:
            print(f"🔍 {key} — would be created/updated (dry-run)")
            stats.created += 1
            continue

        # Attempt to create
        status_code, response_text = create_variable(gitlab_url, token, group_id, var)

        if status_code == 201:
            print(f"✅ {key} — created")
            stats.created += 1

        elif status_code == 409:
            # Variable already exists
            if mode == "overwrite":
                update_code, update_text = update_variable(gitlab_url, token, group_id, var)
                if update_code == 200:
                    print(f"🔄 {key} — updated")
                    stats.updated += 1
                else:
                    print(f"❌ {key} — update failed: {update_code} {update_text}")
                    stats.errors += 1
            else:
                print(f"⏭️  {key} — already exists, skipping")
                stats.skipped += 1

        else:
            print(f"❌ {key} — error: {status_code} {response_text}")
            stats.errors += 1

    return stats


def main():
    parser = argparse.ArgumentParser(description="Import CI/CD variables into a GitLab group")
    parser.add_argument("--group-id", type=int, required=True, help="Target group ID")
    parser.add_argument("--input", "-i", default="variables.json", help="Input file (default: variables.json)")
    parser.add_argument(
        "--mode",
        choices=["skip", "overwrite"],
        default="skip",
        help="Conflict mode: skip — keep existing, overwrite — replace existing (default: skip)",
    )
    parser.add_argument("--url", default=None, help="GitLab URL (or env GITLAB_URL)")
    parser.add_argument("--token", default=None, help="Private token (or env GITLAB_TOKEN)")
    parser.add_argument("--dry-run", action="store_true", help="Simulate the import without making any changes")
    args = parser.parse_args()

    gitlab_url = args.url or os.environ.get("GITLAB_URL", "https://gitlab.com")
    token = args.token or os.environ.get("GITLAB_TOKEN")

    if not token:
        print("❌ Error: provide a token via --token or the GITLAB_TOKEN environment variable")
        sys.exit(1)

    if not os.path.isfile(args.input):
        print(f"❌ Error: file '{args.input}' not found")
        sys.exit(1)

    gitlab_url = gitlab_url.rstrip("/")

    # Load variables from file
    with open(args.input, "r", encoding="utf-8") as f:
        variables = json.load(f)

    print(f"🔄 Importing variables into group ID={args.group_id}")
    print(f"   URL: {gitlab_url}")
    print(f"   File: {args.input}")
    print(f"   Variables: {len(variables)}")
    print(f"   Mode: {args.mode}")
    if args.dry_run:
        print("   ⚡ DRY-RUN — no changes will be applied")
    print()

    # Run import
    stats = import_variables(
        gitlab_url=gitlab_url,
        token=token,
        group_id=args.group_id,
        variables=variables,
        mode=args.mode,
        dry_run=args.dry_run,
    )

    # Summary
    print()
    print("=" * 45)
    print("📊 Results:")
    print(f"   Created:   {stats.created}")
    print(f"   Updated:   {stats.updated}")
    print(f"   Skipped:   {stats.skipped}")
    print(f"   Errors:    {stats.errors}")
    print("=" * 45)

    if stats.errors > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
