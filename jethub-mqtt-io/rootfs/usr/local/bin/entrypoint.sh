#!/bin/bash
# shellcheck disable=SC1091
# entrypoint.sh - Main entrypoint for JetHub GPIO2MQTT addon
#
# Startup sequence:
# 1. Read options from /data/options.json
# 2. Detect JetHub model (if auto)
# 3. Get MQTT settings (auto-discover or manual)
# 4. Generate final config
# 5. Run gpio-unexport.py
# 6. Start gpio2mqtt

set -euo pipefail

# Configuration paths
OPTIONS_FILE="/data/options.json"
CONFIGS_DIR="/etc/gpio2mqtt/configs"
GENERATED_CONFIG="/data/gpio2mqtt.yaml"
GPIO_UNEXPORT_SCRIPT="/etc/gpio2mqtt/gpio-unexport.py"

# Logging functions
log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_debug() {
    if [[ "${LOG_LEVEL:-info}" == "debug" || "${LOG_LEVEL:-info}" == "trace" ]]; then
        echo "[DEBUG] $*"
    fi
}

# Read option from options.json
get_option() {
    local key="$1"
    local default="${2:-}"
    local value
    value=$(jq -r ".$key // empty" "$OPTIONS_FILE" 2>/dev/null || echo "")
    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Get nested option
get_nested_option() {
    local key="$1"
    local default="${2:-}"
    local value
    value=$(jq -r ".$key // empty" "$OPTIONS_FILE" 2>/dev/null || echo "")
    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Discover MQTT settings from Home Assistant Supervisor API
discover_mqtt() {
    log_info "Discovering MQTT settings from Home Assistant..."

    if [[ -z "${SUPERVISOR_TOKEN:-}" ]]; then
        log_error "SUPERVISOR_TOKEN not available, cannot auto-discover MQTT"
        return 1
    fi

    local mqtt_info
    mqtt_info=$(curl -sSL -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        "http://supervisor/services/mqtt" 2>/dev/null || echo "{}")

    if [[ "$mqtt_info" == "{}" ]] || ! echo "$mqtt_info" | jq -e '.data' >/dev/null 2>&1; then
        log_error "Failed to get MQTT info from Supervisor API"
        return 1
    fi

    MQTT_HOST=$(echo "$mqtt_info" | jq -r '.data.host // empty')
    MQTT_PORT=$(echo "$mqtt_info" | jq -r '.data.port // empty')
    MQTT_USER=$(echo "$mqtt_info" | jq -r '.data.username // empty')
    MQTT_PASS=$(echo "$mqtt_info" | jq -r '.data.password // empty')

    # Validate MQTT host was discovered
    if [[ -z "$MQTT_HOST" ]]; then
        log_error "MQTT host not found in Supervisor API response"
        log_error "Please configure MQTT broker in Home Assistant or provide manual MQTT settings"
        return 1
    fi

    log_info "Discovered MQTT: host=$MQTT_HOST, port=$MQTT_PORT, user=$MQTT_USER"
}

# Generate final configuration
generate_config() {
    local base_config="$1"
    local output_config="$2"

    log_info "Generating config from: $base_config"

    # Check for whitespace-only custom config
    local trimmed_config
    trimmed_config=$(echo "${CUSTOM_CONFIG:-}" | tr -d '[:space:]')

    # Start with base config or custom config
    if [[ -n "$trimmed_config" ]]; then
        log_info "Using custom config from addon options"
        echo "$CUSTOM_CONFIG" > "$output_config"
    else
        cp "$base_config" "$output_config"
    fi

    # Export variables for Python script (avoids shell injection)
    export GPIO2MQTT_CONFIG_PATH="$output_config"
    export GPIO2MQTT_MQTT_HOST="$MQTT_HOST"
    export GPIO2MQTT_MQTT_PORT="$MQTT_PORT"
    export GPIO2MQTT_MQTT_USER="$MQTT_USER"
    export GPIO2MQTT_MQTT_PASS="$MQTT_PASS"
    export GPIO2MQTT_MQTT_CLIENT_ID="$MQTT_CLIENT_ID"
    export GPIO2MQTT_MQTT_TOPIC_PREFIX="$MQTT_TOPIC_PREFIX"
    export GPIO2MQTT_MQTT_KEEPALIVE="$MQTT_KEEPALIVE"
    export GPIO2MQTT_MQTT_QOS="$MQTT_QOS"

    # Update MQTT settings using Python (more reliable YAML handling)
    python3 << 'PYTHON_EOF'
import os
import yaml
import sys

# Custom Loader that treats on/off/yes/no as strings, not booleans (YAML 1.1 compat)
# This prevents PyYAML from converting "off" to False
class SafeLoaderNoYAML11Bool(yaml.SafeLoader):
    pass

# Remove implicit resolvers for YAML 1.1 boolean values (on/off/yes/no)
# Keep only true/false as booleans
for ch in list('OoYyNn'):
    if ch in SafeLoaderNoYAML11Bool.yaml_implicit_resolvers:
        SafeLoaderNoYAML11Bool.yaml_implicit_resolvers[ch] = [
            (tag, regexp) for tag, regexp in SafeLoaderNoYAML11Bool.yaml_implicit_resolvers[ch]
            if tag != 'tag:yaml.org,2002:bool'
        ]

# Custom Dumper that quotes strings that look like YAML booleans
# This ensures "off"/"on" stay as strings and aren't reinterpreted
class SafeDumperPreserveStrings(yaml.SafeDumper):
    pass

YAML_BOOL_STRINGS = {'true', 'false', 'yes', 'no', 'on', 'off', 'y', 'n'}

def str_representer(dumper, value):
    # Quote strings that could be interpreted as booleans
    if value.lower() in YAML_BOOL_STRINGS:
        return dumper.represent_scalar('tag:yaml.org,2002:str', value, style="'")
    return dumper.represent_scalar('tag:yaml.org,2002:str', value)

SafeDumperPreserveStrings.add_representer(str, str_representer)

config_path = os.environ.get('GPIO2MQTT_CONFIG_PATH', '')
mqtt_host = os.environ.get('GPIO2MQTT_MQTT_HOST', '')
mqtt_port = os.environ.get('GPIO2MQTT_MQTT_PORT', '')
mqtt_user = os.environ.get('GPIO2MQTT_MQTT_USER', '')
mqtt_pass = os.environ.get('GPIO2MQTT_MQTT_PASS', '')
mqtt_client_id = os.environ.get('GPIO2MQTT_MQTT_CLIENT_ID', '')
mqtt_topic_prefix = os.environ.get('GPIO2MQTT_MQTT_TOPIC_PREFIX', '')
mqtt_keepalive = os.environ.get('GPIO2MQTT_MQTT_KEEPALIVE', '')
mqtt_qos = os.environ.get('GPIO2MQTT_MQTT_QOS', '')

try:
    with open(config_path, 'r') as f:
        config = yaml.load(f, Loader=SafeLoaderNoYAML11Bool)

    if config is None:
        config = {}

    if 'mqtt' not in config:
        config['mqtt'] = {}

    # Update MQTT settings - always set host, delete user/pass if empty (anonymous auth)
    if mqtt_host:
        config['mqtt']['host'] = mqtt_host
    if mqtt_port:
        config['mqtt']['port'] = int(mqtt_port)

    # Handle user/password - delete if empty for anonymous auth
    if mqtt_user:
        config['mqtt']['user'] = mqtt_user
    elif 'user' in config['mqtt']:
        del config['mqtt']['user']

    if mqtt_pass:
        config['mqtt']['password'] = mqtt_pass
    elif 'password' in config['mqtt']:
        del config['mqtt']['password']

    if mqtt_client_id:
        config['mqtt']['client_id'] = mqtt_client_id
    if mqtt_topic_prefix:
        config['mqtt']['topic_prefix'] = mqtt_topic_prefix
    if mqtt_keepalive:
        config['mqtt']['keepalive'] = int(mqtt_keepalive)
    if mqtt_qos:
        config['mqtt']['qos'] = int(mqtt_qos)

    with open(config_path, 'w') as f:
        yaml.dump(config, f, Dumper=SafeDumperPreserveStrings, default_flow_style=False, allow_unicode=True)

    print("[INFO] Config updated successfully")
except Exception as e:
    print(f"[ERROR] Failed to update config: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
}

# Run GPIO unexport script
run_gpio_unexport() {
    local config_file="$1"

    if [[ -f "$GPIO_UNEXPORT_SCRIPT" ]]; then
        log_info "Running GPIO unexport script..."
        python3 "$GPIO_UNEXPORT_SCRIPT" "$config_file" || {
            log_error "GPIO unexport failed, continuing anyway..."
        }
    else
        log_info "GPIO unexport script not found, skipping..."
    fi
}

# Main function
main() {
    log_info "Starting JetHub GPIO2MQTT addon..."

    # Check options file
    if [[ ! -f "$OPTIONS_FILE" ]]; then
        log_error "Options file not found: $OPTIONS_FILE"
        exit 1
    fi

    # Read options
    LOG_LEVEL=$(get_option "log_level" "info")
    JETHUB_MODEL=$(get_option "jethub_model" "auto")
    USE_MODULE_CONFIG=$(get_option "use_module_config" "false")
    CUSTOM_CONFIG=$(get_option "custom_config" "")
    MQTT_CLIENT_ID=$(get_nested_option "mqtt.client_id" "jethub-mqtt-io")
    MQTT_TOPIC_PREFIX=$(get_nested_option "mqtt.topic_prefix" "jethub-mqtt-io")

    # Manual MQTT settings (optional)
    MANUAL_MQTT_HOST=$(get_nested_option "mqtt.host" "")
    MANUAL_MQTT_PORT=$(get_nested_option "mqtt.port" "")
    MANUAL_MQTT_USER=$(get_nested_option "mqtt.user" "")
    MANUAL_MQTT_PASS=$(get_nested_option "mqtt.password" "")

    # Advanced MQTT settings
    MQTT_KEEPALIVE=$(get_nested_option "mqtt.keepalive" "60")
    MQTT_QOS=$(get_nested_option "mqtt.qos" "1")

    log_info "Options: model=$JETHUB_MODEL, use_module=$USE_MODULE_CONFIG, log_level=$LOG_LEVEL"

    # Check for whitespace-only custom config (used in multiple places)
    local trimmed_custom_config
    trimmed_custom_config=$(echo "${CUSTOM_CONFIG:-}" | tr -d '[:space:]')

    # Validate manual mode - custom_config is required
    if [[ "$JETHUB_MODEL" == "manual" ]]; then
        if [[ -z "$trimmed_custom_config" ]]; then
            log_error "Manual mode requires custom_config to be set"
            log_error "Please provide a complete gpio2mqtt YAML configuration in the custom_config field"
            exit 1
        fi
        log_info "Using manual mode with custom configuration"
        # For manual mode, BASE_CONFIG is not used, but we set a dummy value
        BASE_CONFIG=""
    else
        # Detect model if auto
        if [[ "$JETHUB_MODEL" == "auto" ]]; then
            log_info "Auto-detecting JetHub model..."
            # Source the detect-model script
            source /usr/local/bin/detect-model.sh
            JETHUB_MODEL=$(detect_model) || {
                log_error "Failed to detect JetHub model"
                exit 1
            }
            log_info "Detected model: $JETHUB_MODEL"
        fi

        # Determine base config file
        if [[ "$USE_MODULE_CONFIG" == "true" ]]; then
            BASE_CONFIG="${CONFIGS_DIR}/${JETHUB_MODEL}-module.yaml"
        else
            BASE_CONFIG="${CONFIGS_DIR}/${JETHUB_MODEL}.yaml"
        fi

        # Check if base config exists (only if no valid custom config)
        if [[ -z "$trimmed_custom_config" ]]; then
            if [[ ! -f "$BASE_CONFIG" ]]; then
                log_error "Base config not found: $BASE_CONFIG"
                log_error "Available configs:"
                ls -la "$CONFIGS_DIR/" || true
                exit 1
            fi
        fi
    fi

    # Get MQTT settings
    MQTT_HOST=""
    MQTT_PORT=""
    MQTT_USER=""
    MQTT_PASS=""

    # Use manual settings if provided, otherwise auto-discover
    if [[ -n "$MANUAL_MQTT_HOST" ]]; then
        log_info "Using manual MQTT settings"
        MQTT_HOST="$MANUAL_MQTT_HOST"
        MQTT_PORT="${MANUAL_MQTT_PORT:-1883}"
        MQTT_USER="$MANUAL_MQTT_USER"
        MQTT_PASS="$MANUAL_MQTT_PASS"
    else
        log_info "Auto-discovering MQTT settings..."
        discover_mqtt || {
            log_error "MQTT auto-discovery failed and no manual settings provided"
            exit 1
        }
    fi

    # Generate final config
    generate_config "$BASE_CONFIG" "$GENERATED_CONFIG"

    # Run GPIO unexport
    run_gpio_unexport "$GENERATED_CONFIG"

    # Start gpio2mqtt
    log_info "Starting gpio2mqtt..."

    # Set log level for Rust application
    case "$LOG_LEVEL" in
        trace)
            export RUST_LOG="trace"
            ;;
        debug)
            export RUST_LOG="debug"
            ;;
        info)
            export RUST_LOG="info"
            ;;
        warning)
            export RUST_LOG="warn"
            ;;
        error)
            export RUST_LOG="error"
            ;;
        *)
            export RUST_LOG="info"
            ;;
    esac

    # Execute gpio2mqtt (replace this process)
    exec /usr/local/bin/gpio2mqtt --config "$GENERATED_CONFIG"
}

# Run main
main "$@"
