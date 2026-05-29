#!/usr/bin/env python3
"""
Export CI/CD variables from a GitLab group to a JSON file.

Usage:
    export GITLAB_TOKEN=your_private_token
    python export_variables.py --group-id 123 --output variables.json
    python export_variables.py --group-id 123 --output variables.json --url https://gitlab.company.com
"""

import argparse
import json
import os
import sys

import requests


def get_variables(gitlab_url: str, token: str, group_id: int) -> list:
    """Fetch all variables for a group, handling pagination."""
    headers = {"PRIVATE-TOKEN": token}
    variables = []
    page = 1
    per_page = 100

    while True:
        response = requests.get(
            f"{gitlab_url}/api/v4/groups/{group_id}/variables",
            headers=headers,
            params={"page": page, "per_page": per_page},
        )

        if response.status_code == 401:
            print("❌ Authorization error. Check your token.")
            sys.exit(1)
        elif response.status_code == 404:
            print(f"❌ Group with ID={group_id} not found.")
            sys.exit(1)
        elif response.status_code != 200:
            print(f"❌ API error: {response.status_code} — {response.text}")
            sys.exit(1)

        data = response.json()
        if not data:
            break

        variables.extend(data)

        if len(data) < per_page:
            break

        page += 1

    return variables


def main():
    parser = argparse.ArgumentParser(description="Export CI/CD variables from a GitLab group")
    parser.add_argument("--group-id", type=int, required=True, help="Source group ID")
    parser.add_argument("--output", "-o", default="variables.json", help="Output file (default: variables.json)")
    parser.add_argument("--url", default=None, help="GitLab URL (or env GITLAB_URL)")
    parser.add_argument("--token", default=None, help="Private token (or env GITLAB_TOKEN)")
    args = parser.parse_args()

    gitlab_url = args.url or os.environ.get("GITLAB_URL", "https://gitlab.com")
    token = args.token or os.environ.get("GITLAB_TOKEN")

    if not token:
        print("❌ Error: provide a token via --token or the GITLAB_TOKEN environment variable")
        sys.exit(1)

    # Strip trailing slash
    gitlab_url = gitlab_url.rstrip("/")

    print(f"🔄 Exporting variables from group ID={args.group_id}")
    print(f"   URL: {gitlab_url}")
    print(f"   File: {args.output}")
    print()

    # Fetch variables
    variables = get_variables(gitlab_url, token, args.group_id)

    # Save to file
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(variables, f, indent=2, ensure_ascii=False)

    print(f"✅ Exported variables: {len(variables)}")
    print()

    # Print summary list
    print("📋 Variable list:")
    empty_values = 0
    for var in variables:
        value_status = ""
        if not var.get("value"):
            value_status = " ⚠️ (empty value)"
            empty_values += 1

        print(
            f"   - {var['key']} "
            f"[{var.get('variable_type', 'env_var')}] "
            f"protected={var.get('protected', False)} "
            f"masked={var.get('masked', False)} "
            f"scope={var.get('environment_scope', '*')}"
            f"{value_status}"
        )

    if empty_values:
        print()
        print(f"⚠️  Note: {empty_values} variable(s) with empty value")
        print("   (masked variables may not return their value through the API)")


if __name__ == "__main__":
    main()
