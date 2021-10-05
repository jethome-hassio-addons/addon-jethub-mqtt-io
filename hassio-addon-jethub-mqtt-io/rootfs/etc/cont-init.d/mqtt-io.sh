#!/usr/bin/with-contenv bashio

JETHUB_MODEL=$(cat /etc/jethub_model)

MQTT_IO_CONFIG_TEMPLATE=/etc/jethub_configs/$JETHUB_MODEL/mqtt-io.yaml
MQTT_IO_CONFIG=/etc/mqtt-io.conf

if ! test -f "$MQTT_IO_CONFIG_TEMPLATE"; then
  bashio::exit.nok "mqtt-io template config not found at path '$MQTT_IO_CONFIG_TEMPLATE'"
fi

######################################################################

MQTT_HOST=$(bashio::config 'mqtt.host')
MQTT_PORT=$(bashio::config 'mqtt.port')
MQTT_USER=$(bashio::config 'mqtt.user')
MQTT_PASSWORD=$(bashio::config 'mqtt.password')


if ! bashio::services.available "mqtt" && ! bashio::config.exists 'mqtt.host'; then
    bashio::exit.nok "No internal MQTT service found and no MQTT server defined. Please install Mosquitto broker or specify your own."
else
    bashio::log.info "MQTT available, fetching server detail ..."
    if ! bashio::config.exists 'mqtt.host'; then
        bashio::log.info "MQTT server settings not configured, trying to auto-discovering ..."
        MQTT_HOST="$(bashio::services mqtt "host")"
        MQTT_PORT="$(bashio::services mqtt "port")"
        bashio::log.info "Discovered mqtt server: '$MQTT_HOST', port: '$MQTT_PORT'"
    fi
    if ! bashio::config.exists 'mqtt.user'; then
        bashio::log.info "MQTT credentials not configured, trying to auto-discovering ..."
        MQTT_USER=$(bashio::services mqtt "username")
        MQTT_PASSWORD=$(bashio::services mqtt "password")
        bashio::log.info "Discovered mqtt user '$MQTT_USER'"
    fi
fi

if test -z "$MQTT_HOST"; then
  bashio::exit.nok "mqtt.host not configured"
fi

######################################################################

function set_mqtt_io_cfg {
  local var_name="$1"
  local converter="$2"
  local value="$3"
  local tmp_file="$MQTT_IO_CONFIG.tmp"

  if test -z "$value"; then
    yq "del(.${var_name})" "$MQTT_IO_CONFIG" > "$tmp_file"
    bashio::log.debug "$var_name -> DELETE"
  else
    VAR="$value" yq ".${var_name}=(env.VAR|${converter})" "$MQTT_IO_CONFIG" > "$tmp_file"
    if [ "$var_name" == "mqtt.password" ]; then
      bashio::log.debug "$var_name -> ***"
    else
      bashio::log.debug "$var_name -> $value"
    fi
  fi
  mv -f "$tmp_file" "$MQTT_IO_CONFIG"
}

######################################################################

cp "$MQTT_IO_CONFIG_TEMPLATE" "$MQTT_IO_CONFIG"

bashio::log.info "Preparing mqtt-io config to for model: '$JETHUB_MODEL' from '$MQTT_IO_CONFIG_TEMPLATE'"

MQTT_CLIENT_ID=$(bashio::config 'mqtt.client_id')
TOPIC_PREFIX=$(bashio::config 'mqtt.topic_prefix')

######################################################################

set_mqtt_io_cfg "mqtt.host" tostring "$MQTT_HOST"
set_mqtt_io_cfg "mqtt.port" tonumber "$MQTT_PORT"
set_mqtt_io_cfg "mqtt.user" tostring "$MQTT_USER"
set_mqtt_io_cfg "mqtt.password" tostring "$MQTT_PASSWORD"
set_mqtt_io_cfg "mqtt.client_id" tostring "$MQTT_CLIENT_ID"
set_mqtt_io_cfg "mqtt.topic_prefix" tostring "$TOPIC_PREFIX"

