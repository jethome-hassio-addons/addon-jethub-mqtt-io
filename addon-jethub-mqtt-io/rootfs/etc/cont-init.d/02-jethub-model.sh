#!/usr/bin/with-contenv bashio

JETHUB_CONFIGS_BASE_DIR=/etc/jethub_configs


if ! bashio::config.exists 'jethub_model'; then
  bashio::exit.nok "No JetHub model specified (please specify it in config)"
fi

JETHUB_MODEL=$(bashio::config 'jethub_model')

if [ "$JETHUB_MODEL" == "auto" ]; then
  JETHUB_MODEL="" # set to empty
  bashio::log.info "JetHub model was set to 'auto', trying to detect ..."

  #FIXME: detect
  JETHUB_MODEL="jethub_d1_basic"

  if test -z "$JETHUB_MODEL"; then
    bashio::exit.nok "Could not detect JetHub model"
  fi
fi


if ! test -d "$JETHUB_CONFIGS_BASE_DIR/$JETHUB_MODEL"; then
  bashio::exit.nok "Invalid JetHub model: '$JETHUB_MODEL', no configs found"
fi

bashio::log.info "JetHub model: '$JETHUB_MODEL'"

echo "$JETHUB_MODEL" > /etc/jethub_model
