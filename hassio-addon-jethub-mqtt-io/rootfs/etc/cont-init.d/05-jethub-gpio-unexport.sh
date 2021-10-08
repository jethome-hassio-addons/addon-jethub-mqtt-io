#!/usr/bin/with-contenv bashio

JETHUB_MODEL=$(cat /etc/jethub_model)
JETHUB_GLOBAL_CONFIG_FILE=/etc/jethub_configs/$JETHUB_MODEL/global.yaml
UNEXPORTED_PINS_FILE=/tmp/jethub_unexported

if ! test -f "$JETHUB_GLOBAL_CONFIG_FILE"; then
  bashio::exit.nok "Global JetHub config not found at path '$JETHUB_GLOBAL_CONFIG_FILE'"
fi

SYSFS_GPIO_PINS=$(yq '.sysfs_gpio[]' "$JETHUB_GLOBAL_CONFIG_FILE")

# Clear unexported pins file
echo > "$UNEXPORTED_PINS_FILE"

for PIN in $SYSFS_GPIO_PINS
do
  if test -d "/sys/class/gpio/gpio$PIN"; then
    bashio::log.info "Unexporting gpio pin '$PIN' from sysfs"
    sh -c "echo $PIN >/sys/class/gpio/unexport"
    sh -c "echo $PIN >> $UNEXPORTED_PINS_FILE"
  else
    bashio::log.info "pin '$PIN' was not exported, to unexport needed"
  fi
done

