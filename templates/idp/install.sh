#!/bin/sh
set -e
export ANT_OPTS=" \
      -Didp.noprompt=true \
      -Didp.no.tidy=true \
      -Didp.merge.properties={{ shib_idp.src_root }}/install-{{ download.shib_idp.version }}.properties \
      -Didp.src.dir={{ shib_idp.src }} \
      -Didp.target.dir={{ shib_idp.home }} \
      -Didp.host.name={{ idp_host_name }} \
      -Didp.scope={{ idp_attribute_scope }} \
      -Didp.keystore.password={{ shib_idp.keystore_password }} \
      -Didp.sealer.password={{ shib_idp.cookie_enc_key_password }} "
export JAVA_HOME="/usr"
sh {{ shib_idp.src }}/bin/install.sh
