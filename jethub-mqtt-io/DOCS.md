# JetHome JetHub GPIO2MQTT

Expose [JetHome JetHub](https://jethome.ru) GPIO resources (relays, inputs, LEDs) to
Home Assistant via MQTT with autodiscovery support.

## Supported Devices

| Model                | Description                                                           |
| -------------------- | --------------------------------------------------------------------- |
| JetHub H1 (J80)      | JetHome ARM controller                                                |
| JetHub D1/D1+ (J100) | JetHome ARM controller with 4 inputs, 3 relays, status LED            |
| JetHub D2 (J200)     | JetHome ARM controller with 3 inputs, 2 relays, status LED, UXM slots |

## Configuration

**Note**: _Remember to restart the add-on when the configuration is changed._

### Simple Configuration

With auto-detection and MQTT auto-discovery from Home Assistant:

```yaml
log_level: info
jethub_model: auto
use_module_config: false
mqtt:
  client_id: jethub-mqtt-io
  topic_prefix: jethub-mqtt-io
```

### Advanced Configuration

With manual MQTT settings:

```yaml
log_level: info
jethub_model: auto
use_module_config: true
mqtt:
  host: 192.168.1.100
  port: 1883
  user: my_user
  password: my_password
  client_id: jethub-mqtt-io
  topic_prefix: jethub-mqtt-io
```

### Custom Configuration

You can provide a complete custom gpio2mqtt configuration in the `custom_config` field.
MQTT settings from the addon options will still be applied on top of your custom config.

## Options

### Option: `log_level`

Log level for the application.

**Values**: `trace`, `debug`, `info`, `warning`, `error`
**Default**: `info`

### Option: `jethub_model`

JetHub model selection.

**Values**:

- `auto` - Auto-detect JetHub model from device tree
- `jethub-h1` - JetHome JetHub H1 (J80)
- `jethub-d1` - JetHome JetHub D1/D1+ (J100)
- `jethub-d2` - JetHome JetHub D2 (J200)
- `manual` - Use custom configuration (requires `custom_config`)

**Default**: `auto`

### Option: `use_module_config`

Use module configuration variant that includes additional GPIO pins
for ZigBee/UXM module control (BOOT, RESET pins).

**Default**: `false`

### Option: `custom_config`

Optional custom gpio2mqtt YAML configuration. If provided, this will be used
instead of the built-in configuration for your JetHub model.

**Default**: empty

### Group: `mqtt`

MQTT connection settings.

| Option              | Description                                           | Default          |
| ------------------- | ----------------------------------------------------- | ---------------- |
| `mqtt.host`         | MQTT server host (leave blank for auto-discovery)     | auto             |
| `mqtt.port`         | MQTT server port (leave blank for auto-discovery)     | auto             |
| `mqtt.user`         | MQTT server user (leave blank for auto-discovery)     | auto             |
| `mqtt.password`     | MQTT server password (leave blank for auto-discovery) | auto             |
| `mqtt.client_id`    | MQTT client ID                                        | `jethub-mqtt-io` |
| `mqtt.topic_prefix` | MQTT topic prefix                                     | `jethub-mqtt-io` |
| `mqtt.keepalive`    | MQTT keepalive interval (seconds)                     | `60`             |
| `mqtt.qos`          | MQTT QoS level (0, 1, or 2)                           | `1`              |

## MQTT Topics

### Home Assistant Convention

```
{topic_prefix}/input/{name}       # Input state (ON/OFF)
{topic_prefix}/output/{name}      # Output state (ON/OFF)
{topic_prefix}/output/{name}/set  # Output command
{topic_prefix}/status             # Device availability (online/offline)
```

### Home Assistant Discovery

The addon automatically registers devices and entities in Home Assistant
via MQTT discovery. No manual configuration is required.

## Exposed GPIO Resources

### JetHub D1/D1+ (Basic)

| Resource            | Type   | Description        |
| ------------------- | ------ | ------------------ |
| jethub_front_button | Input  | Front panel button |
| jethub_input_1..4   | Input  | Digital inputs     |
| stat_led_red        | Output | Status LED (red)   |
| stat_led_green      | Output | Status LED (green) |
| jethub_relay_1..3   | Output | Relays             |

### JetHub D1/D1+ (Module)

Includes all basic resources plus:

| Resource     | Type   | Description             |
| ------------ | ------ | ----------------------- |
| zigbee_boot  | Output | ZigBee module BOOT pin  |
| zigbee_reset | Output | ZigBee module RESET pin |

### JetHub D2 (Basic)

| Resource           | Type   | Description        |
| ------------------ | ------ | ------------------ |
| jethub_user_button | Input  | Front panel button |
| jethub_input_1..3  | Input  | Digital inputs     |
| jethub_relay_1..2  | Output | Relays             |

### JetHub D2 (Module)

Includes all basic resources plus UXM slot control pins:

| Resource   | Type   | Description          |
| ---------- | ------ | -------------------- |
| uxm1_reset | Output | UXM slot 1 RESET pin |
| uxm1_boot  | Output | UXM slot 1 BOOT pin  |
| uxm2_reset | Output | UXM slot 2 RESET pin |
| uxm2_boot  | Output | UXM slot 2 BOOT pin  |

### JetHub H1 (Basic)

| Resource | Type   | Description |
| -------- | ------ | ----------- |
| stat_led | Output | Status LED  |

### JetHub H1 (Module)

Includes all basic resources plus:

| Resource      | Type   | Description             |
| ------------- | ------ | ----------------------- |
| zigbee_reset  | Output | ZigBee module RESET pin |
| zigbee_boot   | Output | ZigBee module BOOT pin  |
| module2_reset | Output | Module-2 slot RESET pin |
| module2_boot  | Output | Module-2 slot BOOT pin  |

## Troubleshooting

### GPIO Access Issues

If you experience GPIO access issues, ensure that:

1. The addon has GPIO access enabled (should be automatic)
2. No other service is using the same GPIO pins via sysfs

The addon automatically unexports GPIO pins from sysfs before starting.

### MQTT Connection Issues

If MQTT auto-discovery fails:

1. Ensure the Mosquitto broker addon is installed and running
2. Try specifying MQTT settings manually in the addon configuration

### Model Detection Issues

If auto-detection fails:

1. Check addon logs for detection errors
2. Manually specify your JetHub model in the configuration

## Support

- [GitHub Issues](https://github.com/jethome-hassio-addons/addon-jethub-mqtt-io/issues)
- [JetHome Website](https://jethome.ru)
