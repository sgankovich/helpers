#!/bin/bash

# ============================================
# Export CI/CD variables from a GitLab group
# ============================================

GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"
GROUP_ID="${1:-}"
OUTPUT_FILE="${2:-variables.json}"

# --- Validation ---
if [[ -z "$GITLAB_TOKEN" ]]; then
    echo "❌ Error: set the GITLAB_TOKEN environment variable"
    echo "   export GITLAB_TOKEN=your_private_token"
    exit 1
fi

if [[ -z "$GROUP_ID" ]]; then
    echo "❌ Error: provide a group ID"
    echo "   Usage: $0 <group_id> [output_file]"
    echo "   Example: $0 123 variables.json"
    exit 1
fi

# --- Dependency check ---
if ! command -v jq &> /dev/null; then
    echo "❌ Error: 'jq' is required"
    echo "   Install: apt install jq / yum install jq / brew install jq"
    exit 1
fi

echo "🔄 Exporting variables from group ID=$GROUP_ID..."
echo "   URL: $GITLAB_URL"
echo "   File: $OUTPUT_FILE"
echo ""

# --- Fetch variables (with pagination) ---
PAGE=1
PER_PAGE=100
ALL_VARS="[]"

while true; do
    RESPONSE=$(curl --silent --show-error --fail \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "${GITLAB_URL}/api/v4/groups/${GROUP_ID}/variables?page=${PAGE}&per_page=${PER_PAGE}")

    if [[ $? -ne 0 ]]; then
        echo "❌ Error calling GitLab API"
        exit 1
    fi

    # Check if there is data
    COUNT=$(echo "$RESPONSE" | jq 'length')

    if [[ "$COUNT" -eq 0 ]]; then
        break
    fi

    # Append to the combined array
    ALL_VARS=$(echo "$ALL_VARS" "$RESPONSE" | jq -s '.[0] + .[1]')

    if [[ "$COUNT" -lt "$PER_PAGE" ]]; then
        break
    fi

    PAGE=$((PAGE + 1))
done

# --- Save output ---
TOTAL=$(echo "$ALL_VARS" | jq 'length')

echo "$ALL_VARS" | jq '.' > "$OUTPUT_FILE"

echo "✅ Exported variables: $TOTAL"
echo ""

# --- Print variable list ---
echo "📋 Variable list:"
echo "$ALL_VARS" | jq -r '.[] | "   - \(.key) [\(.variable_type)] protected=\(.protected) masked=\(.masked) scope=\(.environment_scope)"'

echo ""
echo "⚠️  Note: masked variables may have empty values (GitLab API limitation)"
