#!/usr/bin/with-contenv bashio

JETHUB_MODEL=$(cat /etc/jethub_model)
GLOBAL_CONFIG=/etc/jethub_configs/$JETHUB_MODEL/global.yaml
UNEXPORTED_PINS_FILE=/tmp/jethub_unexported

if ! test -f "$GLOBAL_CONFIG"; then
  bashio::exit.nok "Global JetHub config not found at path '$GLOBAL_CONFIG'"
fi

SYSFS_GPIO_PINS=$(yq '.sysfs_gpio[]' "$GLOBAL_CONFIG")

# Clear unexported pins file
echo > "$UNEXPORTED_PINS_FILE"

for PIN in $SYSFS_GPIO_PINS
do
  if test -d "/sys/class/gpio/gpio$PIN"; then
    bashio::log.info "Unexporting gpio pin '$PIN' from sysfs"
    echo "$PIN" >/sys/class/gpio/unexport
    echo "$PIN" >> $UNEXPORTED_PINS_FILE
  else
    bashio::log.info "pin '$PIN' was not exported"
  fi
done

