#!/usr/bin/env bash

usage()
{
    echo "Usage: ${0##*/} {start|stop}"
    exit 1
}

[ $# -eq 1 ] || usage

case "$1" in
  start)
    rm -rf {{ install_base }}/shibboleth/jetty/tmp/*
    /bin/bash -c "{{ install_base }}/jetty/current/bin/jetty.sh -d start"

    ;;

  stop)
    /bin/bash -c "{{ install_base }}/jetty/current/bin/jetty.sh stop"
    rm -rf {{ install_base }}/shibboleth/jetty/tmp/*
    
    ;;

  *)
    usage

    ;;
esac

exit 0 
