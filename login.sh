#!/bin/sh -e
#
# Copyright 2017-2019 Hewlett Packard Enterprise Development LP
#

if [ -z $REGISTRY ] || [ -z $DOCKER_USER ] || [ -z $DOCKER_PASS ] ; then
  echo "No registry and associated user and pass"
  exit 1
fi

# Guh, so dirty
docker login -u $DOCKER_USER -p "$DOCKER_PASS" $REGISTRY
