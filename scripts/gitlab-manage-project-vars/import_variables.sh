#!/bin/bash

# ============================================
# Import CI/CD variables into a GitLab group
# ============================================

GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"
GROUP_ID="${1:-}"
INPUT_FILE="${2:-variables.json}"
MODE="${3:-skip}"  # skip | overwrite

# --- Validation ---
if [[ -z "$GITLAB_TOKEN" ]]; then
    echo "❌ Error: set the GITLAB_TOKEN environment variable"
    echo "   export GITLAB_TOKEN=your_private_token"
    exit 1
fi

if [[ -z "$GROUP_ID" ]]; then
    echo "❌ Error: provide a group ID"
    echo "   Usage: $0 <group_id> [input_file] [skip|overwrite]"
    echo "   Example: $0 456 variables.json overwrite"
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "❌ Error: file '$INPUT_FILE' not found"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ Error: 'jq' is required"
    exit 1
fi

TOTAL=$(jq 'length' "$INPUT_FILE")
echo "🔄 Importing variables into group ID=$GROUP_ID..."
echo "   URL: $GITLAB_URL"
echo "   File: $INPUT_FILE"
echo "   Variables: $TOTAL"
echo "   Mode: $MODE (skip — keep existing, overwrite — replace existing)"
echo ""

# --- Counters ---
CREATED=0
SKIPPED=0
UPDATED=0
ERRORS=0

# --- Import loop ---
for row in $(jq -r '.[] | @base64' "$INPUT_FILE"); do
    _jq() {
        echo "$row" | base64 --decode | jq -r "${1} // empty"
    }

    KEY=$(_jq '.key')
    VALUE=$(_jq '.value')
    VAR_TYPE=$(_jq '.variable_type')
    PROTECTED=$(_jq '.protected')
    MASKED=$(_jq '.masked')
    RAW=$(_jq '.raw')
    ENV_SCOPE=$(_jq '.environment_scope')

    # Default values
    VAR_TYPE="${VAR_TYPE:-env_var}"
    PROTECTED="${PROTECTED:-false}"
    MASKED="${MASKED:-false}"
    RAW="${RAW:-false}"
    ENV_SCOPE="${ENV_SCOPE:-*}"

    # Skip variables with empty value (masked)
    if [[ -z "$VALUE" ]]; then
        echo "⚠️  $KEY — empty value (possibly masked), skipping"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Attempt to create
    HTTP_CODE=$(curl --silent --output /dev/null --write-out "%{http_code}" \
        --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "${GITLAB_URL}/api/v4/groups/${GROUP_ID}/variables" \
        --form-string "key=${KEY}" \
        --form-string "value=${VALUE}" \
        --form-string "variable_type=${VAR_TYPE}" \
        --form-string "protected=${PROTECTED}" \
        --form-string "masked=${MASKED}" \
        --form-string "raw=${RAW}" \
        --form-string "environment_scope=${ENV_SCOPE}")

    if [[ "$HTTP_CODE" == "201" ]]; then
        echo "✅ $KEY — created"
        CREATED=$((CREATED + 1))

    elif [[ "$HTTP_CODE" == "409" ]]; then
        # Variable already exists
        if [[ "$MODE" == "overwrite" ]]; then
            # Update it
            HTTP_CODE_UPDATE=$(curl --silent --output /dev/null --write-out "%{http_code}" \
                --request PUT \
                --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                "${GITLAB_URL}/api/v4/groups/${GROUP_ID}/variables/${KEY}?filter[environment_scope]=${ENV_SCOPE}" \
                --form-string "value=${VALUE}" \
                --form-string "variable_type=${VAR_TYPE}" \
                --form-string "protected=${PROTECTED}" \
                --form-string "masked=${MASKED}" \
                --form-string "raw=${RAW}" \
                --form-string "environment_scope=${ENV_SCOPE}")

            if [[ "$HTTP_CODE_UPDATE" == "200" ]]; then
                echo "🔄 $KEY — updated"
                UPDATED=$((UPDATED + 1))
            else
                echo "❌ $KEY — update failed (HTTP $HTTP_CODE_UPDATE)"
                ERRORS=$((ERRORS + 1))
            fi
        else
            echo "⏭️  $KEY — already exists, skipping"
            SKIPPED=$((SKIPPED + 1))
        fi
    else
        echo "❌ $KEY — error (HTTP $HTTP_CODE)"
        ERRORS=$((ERRORS + 1))
    fi
done

# --- Summary ---
echo ""
echo "========================================="
echo "📊 Results:"
echo "   Created:   $CREATED"
echo "   Updated:   $UPDATED"
echo "   Skipped:   $SKIPPED"
echo "   Errors:    $ERRORS"
echo "========================================="
