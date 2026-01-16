#!/bin/bash
# detect-model.sh - Detect JetHub controller model
#
# Detection order:
# 1. Home Assistant Supervisor API (http://supervisor/info) - primary method
# 2. Fallback: /sys/firmware/devicetree/base/model
# 3. Fallback: /sys/firmware/devicetree/base/compatible

set -euo pipefail

# List of supported JetHub models
SUPPORTED_MODELS="jethub-d1 jethub-d2 jethub-h1"

# Check if model is supported
is_supported_model() {
    local model="$1"
    for supported in $SUPPORTED_MODELS; do
        if [[ "$model" == "$supported" ]]; then
            return 0
        fi
    done
    return 1
}

# Detect via Home Assistant Supervisor API
detect_via_supervisor_api() {
    # Check for SUPERVISOR_TOKEN
    if [[ -z "${SUPERVISOR_TOKEN:-}" ]]; then
        echo "[detect-model] SUPERVISOR_TOKEN not available, skipping Supervisor API" >&2
        return 1
    fi

    local response
    response=$(curl -s --connect-timeout 5 --max-time 10 \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        "http://supervisor/info" 2>/dev/null) || {
        echo "[detect-model] Failed to connect to Supervisor API" >&2
        return 1
    }

    # Check response is valid
    if ! echo "$response" | jq -e '.result == "ok"' >/dev/null 2>&1; then
        echo "[detect-model] Supervisor API returned error or invalid response" >&2
        return 1
    fi

    local machine
    machine=$(echo "$response" | jq -r '.data.machine // empty')

    if [[ -z "$machine" ]]; then
        echo "[detect-model] No machine field in Supervisor API response" >&2
        return 1
    fi

    # Check if this is a supported JetHub model
    if is_supported_model "$machine"; then
        echo "[detect-model] Detected via Supervisor API: machine=$machine" >&2
        echo "$machine"
        return 0
    else
        echo "[detect-model] Machine '$machine' is not a supported JetHub model" >&2
        return 1
    fi
}

# Detect via /sys/firmware/devicetree/base/model
detect_via_dt_model() {
    if [[ ! -f /sys/firmware/devicetree/base/model ]]; then
        return 1
    fi

    local dt_model
    dt_model=$(tr -d '\0' < /sys/firmware/devicetree/base/model)

    local model=""
    case "$dt_model" in
        "JetHome JetHub J80")
            model="jethub-h1"
            ;;
        "JetHome JetHub D1 (J100)")
            model="jethub-d1"
            ;;
        "JetHome JetHub D2")
            model="jethub-d2"
            ;;
    esac

    if [[ -n "$model" ]]; then
        echo "[detect-model] Detected via /sys/firmware/devicetree/base/model: $dt_model -> $model" >&2
        echo "$model"
        return 0
    fi

    return 1
}

# Detect via /sys/firmware/devicetree/base/compatible
detect_via_dt_compatible() {
    if [[ ! -f /sys/firmware/devicetree/base/compatible ]]; then
        return 1
    fi

    local compatible
    compatible=$(tr '\0' '\n' < /sys/firmware/devicetree/base/compatible)

    local model=""
    if echo "$compatible" | grep -q "jethome,jethub-j80"; then
        model="jethub-h1"
        echo "[detect-model] Detected via compatible: jethome,jethub-j80 -> $model" >&2
    elif echo "$compatible" | grep -q "jethome,jethub-j100"; then
        model="jethub-d1"
        echo "[detect-model] Detected via compatible: jethome,jethub-j100 -> $model" >&2
    elif echo "$compatible" | grep -q "jethome,jethub-j200"; then
        model="jethub-d2"
        echo "[detect-model] Detected via compatible: jethome,jethub-j200 -> $model" >&2
    fi

    if [[ -n "$model" ]]; then
        echo "$model"
        return 0
    fi

    return 1
}

detect_model() {
    local model=""

    # Step 1: Try to detect via Supervisor API (primary method)
    model=$(detect_via_supervisor_api) && {
        echo "$model"
        return 0
    }

    # Step 2: Fallback to /sys/firmware/devicetree/base/model
    model=$(detect_via_dt_model) && {
        echo "$model"
        return 0
    }

    # Step 3: Fallback to /sys/firmware/devicetree/base/compatible
    model=$(detect_via_dt_compatible) && {
        echo "$model"
        return 0
    }

    # Could not detect model
    echo "[detect-model] ERROR: Could not detect JetHub model" >&2
    echo "[detect-model] Supervisor API: SUPERVISOR_TOKEN not available or API error" >&2
    echo "[detect-model] /sys/firmware/devicetree/base/model: not found or unknown" >&2
    echo "[detect-model] /sys/firmware/devicetree/base/compatible: not found or unknown" >&2
    return 1
}

# If script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    detect_model
fi
