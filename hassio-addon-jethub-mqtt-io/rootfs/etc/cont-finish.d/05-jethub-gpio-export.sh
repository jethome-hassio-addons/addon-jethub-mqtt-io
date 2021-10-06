#!/usr/bin/with-contenv bashio

UNEXPORTED_PINS_FILE=/tmp/jethub_unexported

if ! test -f "$UNEXPORTED_PINS_FILE"; then
  bashio::log.info "No any GPIO pin were unexported. Nothing to restore"
  exit 0
fi

UNEXPORTED_PINS=$(cat "$UNEXPORTED_PINS_FILE")

for PIN in $UNEXPORTED_PINS
do
  bashio::log.info "Restore exported GPIO pin '$PIN' back to sysfs"
  sh -c "echo $PIN > /sys/class/gpio/export"
done
