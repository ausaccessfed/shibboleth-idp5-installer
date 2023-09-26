#!/bin/bash
set -e

#
# ------------------------ END BOOTRAP CONFIGURATION ---------------------------

# Supported Operating Systems
#
# Fedora like
#   rhel    - REDHat Linux 7 and 8
#   centos  - CentOS 7, 8 and Stream
#   ol      - ORACLE Linux 7 and 8
#   rocky   - Rocky Linux 8
#
# Debian like
#   ubuntu - Ubuntu 20.04 (Focal Fossa)
#  
function setup_valid_oss {
    APT_LIST="ubuntu"
    YUM_LIST="rhel centos ol rocky"
    OS_LIST="$APT_LIST $YUM_LIST"
}

function set_internal_variables {
    LOCAL_REPO=$INSTALL_BASE/shibboleth-idp4-installer/repository
    SHIBBOLETH_IDP_INSTANCE=$INSTALL_BASE/shibboleth/shibboleth-idp/current
    ANSIBLE_HOSTS_FILE=$LOCAL_REPO/ansible_hosts
    ANSIBLE_HOST_VARS=$LOCAL_REPO/host_vars/$HOST_NAME
    ANSIBLE_CFG=$LOCAL_REPO/ansible.cfg
    DEPLOY_IDP_SCRIPT=$LOCAL_REPO/deploy
    UPGRADE_IDP_SCRIPT=$LOCAL_REPO/upgrade
    ASSETS=$LOCAL_REPO/assets/$HOST_NAME
    CREDENTIAL_BACKUP_PATH=$ASSETS/idp/credentials
    LDAP_PROPERTIES=$ASSETS/idp/conf/ldap.properties
    SECRETS_PROPERTIES=$ASSETS/idp/credentials/secrets.properties
    ACTIVITY_LOG=$INSTALL_BASE/shibboleth-idp4-installer/activity.log

    GIT_REPO=https://github.com/ausaccessfed/shibboleth-idp4-installer.git
    GIT_BRANCH=master

    FR_TEST_REG=https://manager.test.aaf.edu.au/federationregistry/registration/idp
    FR_PROD_REG=https://manager.aaf.edu.au/federationregistry/registration/idp
}


function ensure_mandatory_variables_set {
  for var in HOST_NAME ENVIRONMENT ORGANISATION_NAME ORGANISATION_BASE_DOMAIN \
    HOME_ORG_TYPE SOURCE_ATTRIBUTE_ID INSTALL_BASE OS_UPDATE FIREWALL \
    ENABLE_BACKCHANNEL ENABLE_EDUGAIN IDP_BEHIND_PROXY DEFAULT_ENCRYPTION; do
    if [ ! -n "${!var:-}" ]; then
      echo "Variable '$var' is not set! Set this in `basename $0`"
      exit 1
    fi
  done

  if [ $OS_UPDATE != "true" ] && [ $OS_UPDATE != "false" ]
  then
     echo "Variable OS_UPDATE must be either true or false"
     exit 1
  fi

  if [ $FIREWALL != "firewalld" ] && [ $FIREWALL != "none" ]
  then
    echo "Variable FIREWALL must be one of firewalld or none"
    exit 1
  fi

  if [ $FIREWALL == "none" ]
  then
    echo ""
    echo "WARNING: You have selected to not have the installer maintain"
    echo "         your local server firewall. This may put your IdP at"
    echo "         risk!"
    echo ""
  fi

  if [ $ENABLE_BACKCHANNEL != "true" ] && [ $ENABLE_BACKCHANNEL != "false" ]
  then
     echo "Variable ENABLE_BACKCHANNEL must be either true or false"
     exit 1
  fi

  if [ $ENABLE_EDUGAIN != "true" ] && [ $ENABLE_EDUGAIN != "false" ]
  then
     echo "Variable ENABLE_EDUGAIN must be either true or false"
     exit 1
  fi

  if [ $IDP_BEHIND_PROXY != "true" ] && [ $IDP_BEHIND_PROXY != "false" ]
  then
     echo "Variable IDP_BEHIND_PROXY must be either true or false"
     exit 1
  fi

  if [ $DEFAULT_ENCRYPTION != "GCM" ] && [ $DEFAULT_ENCRYPTION != "CBC" ]
  then
     echo "Variable DEFAULT_ENCRYPTION must be either GCM or CBC"
     exit 1
  fi
}

function ensure_install_base_exists {
  if [ ! -d "$INSTALL_BASE" ]; then
    echo "The directory $INSTALL_BASE where you have requested the install"
    echo "to occur does not exist. Please create this directory before"
    echo "contining."
    exit 1
  fi
}


function install_apt_dependencies {
  if [ $OS_UPDATE == "true" ]
  then
    apt-get upgrade -y
  else
    count_updates=`apt-get upgrade --dry-run | grep "The following packages will be upgraded:" | wc -l`

    echo "WARNING: Automatic server software updates performed by this"
    echo "         installer have been disabled!"
    echo ""
    if (( $count_updates == 0 ))
    then
        echo "There are no patches or updates that are currently outstanding" \
             "for this server,"
        echo "however we recommend that you patch your server software" \
             "regularly!"
    else
        echo "There are currently a number of patches or update that are" \
             "outstanding on this server"
        echo "Use 'apt-get upgrade' to update to following software!"
        echo ""

        apt-get upgrade --dry-run

        echo ""
        echo "We recommend that you patch your server software regularly!"
    fi
  fi
  echo "Install git"
  apt-get -qq -y install git

  echo ""
  echo "Install ansible"
  apt-get -qq -y install ansible

  if [ $FIREWALL == "firewalld" ]
  then
    echo ""
    echo "Install firewalld"
     apt-get -qq -y install firewalld
  fi

  if [ $FIREWALL == "iptables" ]
  then
    echo ""
    echo "Install iptables"
     apt-get -qq -y install iptables-services system-config-firewall-base
  fi
}

function install_yum_dependencies {
  if [ $OS_UPDATE == "true" ]
  then
    yum -y update
  else
    count_updates=`yum check-update --quiet | grep '^[[:alnum:]]' | wc -l`
   
    echo "WARNING: Automatic server software updates performed by this"
    echo "         installer have been disabled!"
    echo ""
    if (( $count_updates == 0 ))
    then
        echo "There are no patches or updates that are currently outstanding" \
             "for this server,"
        echo "however we recommend that you patch your server software" \
             "regularly!"
    else
        echo "There are currently $count_updates patches or update that are" \
             "outstanding on this server"
        echo "Use 'yum update' to update to following software!"
	echo ""

        yum list updates --quiet

        echo ""
        echo "We recommend that you patch your server software regularly!"
    fi
  fi
  echo "Install git"
  yum -y -q -e0 install git

  echo ""
  echo "Install ansible"
  yum -y -q -e0 install ansible

  if [ $FIREWALL == "firewalld" ]
  then
    echo ""
    echo "Install firewalld"
    yum -y -q -e0 install firewalld
  fi

  if [ $FIREWALL == "iptables" ]
  then
    echo ""
    echo "Install iptables"
    yum -y -q -e0 install iptables-services system-config-firewall-base
  fi
}

function pull_repo {
  pushd $LOCAL_REPO > /dev/null
  git pull
  popd > /dev/null
}

function setup_repo {
  if [ -d "$LOCAL_REPO" ]; then
    echo "$LOCAL_REPO already exists, not cloning repository"
    pull_repo
  else
    mkdir -p $LOCAL_REPO
    git clone -b $GIT_BRANCH $GIT_REPO $LOCAL_REPO
  fi
}

function set_ansible_hosts {
  if [ ! -f $ANSIBLE_HOSTS_FILE ]; then
    cat > $ANSIBLE_HOSTS_FILE << EOF
[idp_servers]
$HOST_NAME
EOF
  else
    echo "$ANSIBLE_HOSTS_FILE already exists, not creating hostfile"
  fi
}

function replace_property {
# There will be a space between the property and its value.
  local property1=$1
  local property2="`echo $1 | sed 's/ \*/ /'`"
  local value=$2
  local file=$3
  if [ ! -z "$value" ]; then
    sed -i "s/^$property1.*/$property2 $value/g" $file
  fi
}

function replace_property_nosp {
# There will be NO space between the property and its value.
  local property=$1
  local value=$2
  local file=$3
  if [ ! -z "$value" ]; then
    sed -i "s/^$property.*/$property$value/g" $file
  fi
}


function set_ansible_host_vars {
  if [[ -z $ENTITY_ID ]]; then
    local entity_id="https:\/\/$HOST_NAME\/idp\/shibboleth"
  else
    local entity_id="`echo $ENTITY_ID | sed 's:/:\\\\/:g'`"
  fi
  replace_property 'idp_host_name:' "\"$HOST_NAME\"" $ANSIBLE_HOST_VARS
  replace_property 'idp_entity_id:' "\"$entity_id\"" $ANSIBLE_HOST_VARS
  replace_property 'idp_attribute_scope:' "\"$ORGANISATION_BASE_DOMAIN\"" \
    $ANSIBLE_HOST_VARS
  replace_property 'organisation_name:' "\"$ORGANISATION_NAME\"" \
    $ANSIBLE_HOST_VARS
  replace_property 'home_organisation:' "\"$ORGANISATION_BASE_DOMAIN\"" \
    $ANSIBLE_HOST_VARS
  replace_property 'home_organisation_type:' "\"$HOME_ORG_TYPE\"" \
    $ANSIBLE_HOST_VARS
  replace_property 'server_patch:' "\"$OS_UPDATE\"" \
    $ANSIBLE_HOST_VARS
  replace_property 'firewall:' "\"$FIREWALL\"" \
    $ANSIBLE_HOST_VARS
  replace_property 'enable_backchannel:' "\"$ENABLE_BACKCHANNEL\"" \
    $ANSIBLE_HOST_VARS
  replace_property 'enable_edugain:' "\"$ENABLE_EDUGAIN\"" \
    $ANSIBLE_HOST_VARS
  replace_property 'idp_behind_proxy:' "\"$IDP_BEHIND_PROXY\"" \
    $ANSIBLE_HOST_VARS
  replace_property 'default_encryption:' "\"$DEFAULT_ENCRYPTION\"" \
    $ANSIBLE_HOST_VARS
  replace_property 'old_source_persistent_id:' "\"$SOURCE_ATTRIBUTE_ID\"" \
    $ANSIBLE_HOST_VARS
  replace_property 'source_persistent_id:' "\"$PERSISTENT_ATTRIBUTE_ID\"" \
    $ANSIBLE_HOST_VARS
  if [ $DO_APT == "true" ]; then
      replace_property 'patch_with:' 'apt' $ANSIBLE_HOST_VARS
  fi
  if [ $DO_YUM == "true" ]; then
      replace_property 'patch_with:' 'yum' $ANSIBLE_HOST_VARS
      
  fi
  if [ -n "$FTICKS_KEY_ID" ]; then
     replace_property 'fticks_key_id:' "\"$FTICKS_KEY_ID"\" $ANSIBLE_HOST_VARS
  fi
  if [ -n "$FTICKS_SECRET_KEY" ]; then
     replace_property 'fticks_secret_key:' "\"$FTICKS_SECRET_KEY"\" $ANSIBLE_HOST_VARS
  fi
}

function set_ansible_cfg_log_path {
echo $ANSIBLE_CFG
  replace_property_nosp 'log_path=' "${ACTIVITY_LOG////\\/}" \
    $ANSIBLE_CFG
}

function set_update_idp_script_cd_path {
  replace_property_nosp 'the_install_base=' "${INSTALL_BASE////\\/}" \
    $DEPLOY_IDP_SCRIPT
  replace_property_nosp 'the_install_base=' "${INSTALL_BASE////\\/}" \
    $UPGRADE_IDP_SCRIPT
}

function set_ldap_properties {
  local ldap_url="`echo $LDAP_URL | sed 's:/:\\\\/:g'`"
  replace_property 'idp.authn.LDAP.ldapURL *=' \
    "$ldap_url" $LDAP_PROPERTIES
  replace_property 'idp.authn.LDAP.baseDN *=' \
    "$LDAP_BASE_DN" $LDAP_PROPERTIES
  replace_property 'idp.authn.LDAP.bindDN *=' \
    "$LDAP_BIND_DN" $LDAP_PROPERTIES
  replace_property 'idp.authn.LDAP.bindDNCredential *=' \
    "$LDAP_BIND_DN_PASSWORD" $SECRETS_PROPERTIES
  replace_property 'idp.authn.LDAP.userFilter *=' \
    "($LDAP_USER_FILTER_ATTRIBUTE={user})" $LDAP_PROPERTIES
  RES_PRI='$resolutionContext.principal'
  replace_property 'idp.attribute.resolver.LDAP.searchFilter *=' \
    "($LDAP_USER_FILTER_ATTRIBUTE=$RES_PRI)" $LDAP_PROPERTIES
}

function create_ansible_assets {
echo "Host: $HOST_NAME"
  cd $LOCAL_REPO
  bash create_assets.sh $HOST_NAME $ENVIRONMENT
}

function create_self_signed_certs {
  if [ ! -s $ASSETS/tls/server.key ] &&
     [ ! -s $ASSETS/tls/server.crt ] &&
     [ ! -s $ASSETS/tls/intermediate.crt ]; then
    openssl genrsa -out $ASSETS/tls/server.key 2048
    openssl req -new -x509 -key $ASSETS/tls/server.key \
      -out $ASSETS/tls/server.crt -sha256 -subj "/CN=$HOST_NAME/"
    cp $ASSETS/tls/server.crt $ASSETS/tls/intermediate.crt
  else
    echo "Webservere keypair ($ASSETS/tls) already exists, skipping"
  fi
}

function run_ansible {
  pushd $LOCAL_REPO > /dev/null
  ansible-playbook -i ansible_hosts site_v4.yml --force-handlers --extra-var="install_base=$INSTALL_BASE"
  popd > /dev/null
}

function backup_shibboleth_credentials {
  if [ ! -d "$CREDENTIAL_BACKUP_PATH" ]; then
    mkdir $CREDENTIAL_BACKUP_PATH
  fi

  cp -R $SHIBBOLETH_IDP_INSTANCE/credentials/idp-backchannel.crt $CREDENTIAL_BACKUP_PATH
  cp -R $SHIBBOLETH_IDP_INSTANCE/credentials/idp-backchannel.p12 $CREDENTIAL_BACKUP_PATH
  cp -R $SHIBBOLETH_IDP_INSTANCE/credentials/idp-encryption.crt $CREDENTIAL_BACKUP_PATH
  cp -R $SHIBBOLETH_IDP_INSTANCE/credentials/idp-encryption.key $CREDENTIAL_BACKUP_PATH
  cp -R $SHIBBOLETH_IDP_INSTANCE/credentials/idp-signing.crt $CREDENTIAL_BACKUP_PATH
  cp -R $SHIBBOLETH_IDP_INSTANCE/credentials/idp-signing.key $CREDENTIAL_BACKUP_PATH
  cp -R $SHIBBOLETH_IDP_INSTANCE/credentials/sealer.jks $CREDENTIAL_BACKUP_PATH
  cp -R $SHIBBOLETH_IDP_INSTANCE/credentials/sealer.kver $CREDENTIAL_BACKUP_PATH
  
}

function display_fr_idp_registration_link {
  if [ "$ENVIRONMENT" == "test" ]; then
    echo "$FR_TEST_REG"
  else
    echo "$FR_PROD_REG"
  fi
}

function display_completion_message {
  cat << EOF

Bootstrap finished!

To make your IdP functional follow these steps:

1. Register your IdP in Federation Registry:
   `display_fr_idp_registration_link`

   - For 'Step 3. SAML Configuration' we suggest using the "Easy registration
     using defaults" with the value 'https://$HOST_NAME'

   - For 'Step 4. Attribute Scope' use '$ORGANISATION_BASE_DOMAIN'.

   - For 'Step 5. Cryptography'

       * For the 'Signing Certificate' paste the contents of $SHIBBOLETH_IDP_INSTANCE/credentials/idp-signing.crt
       * For the 'Backchannel Certificate' paste the contents of $SHIBBOLETH_IDP_INSTANCE/credentials/idp-backchannel.crt
       * For the 'Encryption Certificate' paste the contents of $SHIBBOLETH_IDP_INSTANCE/credentials/idp-encryption.crt

   - For 'Step 6. Supported Attributes' select the following:
       * auEduPersonSharedToken
       * commonName
       * displayName
       * eduPersonAffiliation
       * eduPersonAssurance
       * eduPersonScopedAffiliation
       * eduPersonTargetedID
       * email
       * organizationName
       * surname
       * givenName
       * eduPersonOrcid
       * eduPersonPrincipalName
       * homeOrganization
       * homeOrganizationType

   After completing this form, you will receive an email from the federation
   indicating your IdP is pending.

   You should now continue with the installation steps documented at
   https://aaf.freshdesk.com/a/solutions/articles/19000119755

EOF
}

function prevent_duplicate_execution {
  touch "/root/.lock-idp-bootstrap-v4"
}

function duplicate_execution_warning {
  if [ -e "/root/.lock-idp-bootstrap-v4" ]
  then
    echo -e "\n\n-----"
    echo "The bootstrap process has already been executed and could be destructive if run again."
    echo "It is likely you want to run an deploy instead."
    echo "Please see https://aaf.freshdesk.com/a/solutions/articles/19000119755 for further details."
    echo -e "\n\nIn certain cases you may need to re-run the bootstrap process if you've made an error"
    echo "during initial installation. Please see"
    echo "https://aaf.freshdesk.com/a/solutions/articles/19000119754#Reasons-to-re-run-the-installer"
    echo "to disable this warning."
    echo -e "-----\n\n"
    exit 0
  fi
}

function read_bootstrap_ini {
    ini="$(<$1)"                # read the file
    ini="${ini//[/\\[}"          # escape [
    ini="${ini//]/\\]}"          # escape ]
    IFS=$'\n' && ini=( ${ini} ) # convert to line-array
    ini=( ${ini[*]//;*/} )      # remove comments with ;
    ini=( ${ini[*]//#*/} )      # remove comments with #
    ini=( ${ini[*]/\    =/=} )  # remove tabs before =
    ini=( ${ini[*]/=\   /=} )   # remove tabs after =
    ini=( ${ini[*]/\ =\ /=} )   # remove anything with a space around =
    ini=( ${ini[*]/#\\[/\}$'\n'cfg.section.} ) # set section prefix
    ini=( ${ini[*]/%\\]/ \(} )    # convert text2function (1)
    ini=( ${ini[*]/=/=\( } )    # convert item to array
    ini=( ${ini[*]/%/ \)} )     # close array parenthesis
    ini=( ${ini[*]/%\\ \)/ \\} ) # the multiline trick
    ini=( ${ini[*]/%\( \)/\(\) \{ :} ) # convert text2function (2) with noop :
                                       # in case there are no values
    ini=( ${ini[*]/%\} \)/\}} ) # remove extra parenthesis
    ini[0]="" # remove first element
    ini[${#ini[*]} + 1]='}'    # add the last brace
    eval "$(echo "${ini[*]}")" # eval the result
}

function run_as_root {
    if [[ $USER != "root" ]]; then
        echo "bootstrap-v4.sh MUST be run as root!"
        exit 1
    fi
}

function run_on_os {
    if [ -f "/etc/os-release" ]; then
        . /etc/os-release

        if [[ $OS_LIST =~ (^|[[:space:]])"$ID"($|[[:space:]]) ]]; then
           echo "Preparing to install Shibboleth IdP on $ID OS"
           echo ""
           DO_APT="false"
           DO_YUM="false"
           if [[ $YUM_LIST =~ (^|[[:space:]])"$ID"($|[[:space:]]) ]]; then
               DO_YUM="true"
           fi
           if [[ $APT_LIST =~ (^|[[:space:]])"$ID"($|[[:space:]]) ]]; then
               DO_APT="true"
           fi
        else
           echo "$ID is not currently supported by the Installer!"
           exit 1 
        fi
    else
       echo "File /etc/os-release does not exist, can not determine Operating System ID!"
       exit 1
    fi
}

function get_cfg_section {

    if [[ $(declare -F cfg.section.$1) ]]; then
        cfg.section.$1
    else
       echo "Section [$1] not found in bootstrap-v4.ini"
       exit 1
    fi
}

function bootstrap {
  setup_valid_oss
  run_as_root
  run_on_os
  read_bootstrap_ini 'bootstrap-v4.ini'
  get_cfg_section main
  get_cfg_section logging
  get_cfg_section ldap
  get_cfg_section advanced
  set_internal_variables 
  ensure_mandatory_variables_set
  ensure_install_base_exists
  duplicate_execution_warning
  if [ $DO_APT == "true" ]; then
      install_apt_dependencies
  fi
  if [ $DO_YUM == "true" ]; then
      install_yum_dependencies
  fi
  setup_repo
  set_ansible_hosts
  create_ansible_assets
  set_ansible_host_vars
  set_update_idp_script_cd_path
  set_ansible_cfg_log_path

  if [ ${LDAP_URL} ]; then
    set_ldap_properties
  fi

  create_self_signed_certs
  run_ansible
  backup_shibboleth_credentials
  display_completion_message
  prevent_duplicate_execution
}

bootstrap

