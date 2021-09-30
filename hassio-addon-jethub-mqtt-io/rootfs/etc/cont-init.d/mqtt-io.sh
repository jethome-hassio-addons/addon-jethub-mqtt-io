#!/usr/bin/with-contenv bashio

MQTT_SERVER=$(bashio::config 'mqtt.server')
MQTT_USER=$(bashio::config 'mqtt.user')
MQTT_PASSWORD=$(bashio::config 'mqtt.password')
BASE_TOPIC=$(bashio::config 'mqtt.base_topic')


if ! bashio::services.available "mqtt" && ! bashio::config.exists 'mqtt.server'; then
    bashio::exit.nok "No internal MQTT service found and no MQTT server defined. Please install Mosquitto broker or specify your own."
else
    bashio::log.info "MQTT available, fetching server detail ..."
    if ! bashio::config.exists 'mqtt.server'; then
        bashio::log.info "MQTT server settings not configured, trying to auto-discovering ..."
        MQTT_PREFIX="mqtt://"
        if [ "$(bashio::services mqtt "ssl")" = true ]; then
            MQTT_PREFIX="mqtts://"
        fi
        MQTT_SERVER="$MQTT_PREFIX$(bashio::services mqtt "host"):$(bashio::services mqtt "port")"
        bashio::log.info "Configuring '$MQTT_SERVER' mqtt server"
    fi
    if ! bashio::config.exists 'mqtt.user'; then
        bashio::log.info "MQTT credentials not configured, trying to auto-discovering ..."
        MQTT_USER=$(bashio::services mqtt "username")
        MQTT_PASSWORD=$(bashio::services mqtt "password")
        bashio::log.info "Configuring'$MQTT_USER' mqtt user"
    fi
fi

CONFIG_TEMPLATE=/etc/jethub/templates/jethub_d1_basic.yaml

# TODO: parse efuse for CONFIG_TEMPLATE

bashio::log.info "Adjusting yaml config with add-on quirks ..."
cat < "$CONFIG_TEMPLATE" \
    | MQTT_USER="$MQTT_USER"  yq '.mqtt.user=env.MQTT_USER' \
    | MQTT_PASSWORD="$MQTT_PASSWORD" yq '.mqtt.password=env.MQTT_PASSWORD' \
    | MQTT_SERVER="$MQTT_SERVER" yq '.mqtt.host=env.MQTT_SERVER' \
    | BASE_TOPIC="$BASE_TOPIC" yq '.mqtt.topic_prefix=env.BASE_TOPIC' \
    > /etc/mqtt-io.conf


