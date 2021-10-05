#!/usr/bin/with-contenv bashio

UNEXPORTED_PINS_FILE=/tmp/jethub_unexported
UNEXPORTED_PINS=$(cat "$UNEXPORTED_PINS_FILE")

for PIN in $UNEXPORTED_PINS
do
  bashio::log.info "Restore exported pin '$PIN' back to sysfs"
  echo "$PIN" > /sys/class/gpio/export
done
