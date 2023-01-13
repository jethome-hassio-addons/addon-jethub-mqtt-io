# JetHome JetHub mqtt-io peripheral exposer

Expose [JetHome JetHub](http://jethome.ru) resources (relays,inputs,etc..) to
Home Assistant via [mqtt-io](https://github.com/flyte/mqtt-io)

## Configuration

**Note**: _Remember to restart the add-on when the configuration is changed._

**Note**: _All used GPIOs will **disappear** from **/sys/class/gpio** during addon run_

Simple add-on configuration (mqtt will be discovered from the Home Assistant supervisor):

```yaml
log_level: info
jethub_model: auto
mqtt:
  client_id: jethub-mqtt-io
  topic_prefix: jethub-mqtt-io
```


Advanced add-on configuration:

```yaml
log_level: info
jethub_model: auto
mqtt:
  host: 172.17.0.1
  port: 1883
  user: my_user
  password: my_password
  client_id: jethub-mqtt-io
  topic_prefix: jethub-mqtt-io
```

### Option: `log_level`

Log level. 

One of: trace, debug, info, notice, warning, error, fatal

### Option: `jethub_model`

JetHub model.

- `auto`: Auto-discovery.
- `jethub_d1_basic`: [JetHome JetHub D1](http://jethome.ru/jethub-d1) (Basic version with 3 relays, 4 inputs and 1-wire).

### Group: `mqtt`

- `mqtt.host`: MQTT server host (leave blank for auto-discovery)
- `mqtt.port`: MQTT server port (leave blank for auto-discovery)
- `mqtt.user`: MQTT server user (leave blank for auto-discovery)
- `mqtt.password`: MQTT server password (leave blank for auto-discovery)
- `mqtt.client_id`: MQTT client id.
- `mqtt.topic_prefix`: MQTT topic prefix
 
