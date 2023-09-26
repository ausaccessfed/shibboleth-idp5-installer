#!/bin/bash
set -e

HOST_NAME=$1
ENVIRONMENT=$2
TEMPLATE_HOST=idp.example.edu.dist
HOST_VAR="host_vars/$HOST_NAME"
ASSETS="assets/$HOST_NAME"

function create_assets {
  if [ -d "$ASSETS" ]; then
    echo "$ASSETS already exists, skipping"
  else
    mkdir $ASSETS
    cp -R assets/$TEMPLATE_HOST/* $ASSETS
  fi
}

function create_host_var {
  if [ ! -f $HOST_VAR ]; then
    cp host_vars/$TEMPLATE_HOST.$ENVIRONMENT $HOST_VAR
  else
    echo "$HOST_VAR already exists, skipping"
  fi
}

function setup_assets {
  create_host_var
  create_assets
}

if [ "$#" -eq 2 ]
then
  setup_assets
else
  echo "Usage: `basename $0` <hostname> <environment>"
  exit 1
fi

