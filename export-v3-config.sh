#!/usr/bin/env bash

PROGNAME="$(basename $0)"

error_exit()
{
    echo "${PROGNAME}: ${1:-"Unknown Error"}" 1>&2
    exit 1
}

create_output_dir ()
{
    out_dir=$the_install_base/shibboleth-idp-installer/V3-export

    if [[ -e $out_dir ]]; then
        error_exit 'Error - Unable to create output directory, one already exists'
    else
        mkdir $out_dir
    fi
}

get_host_name ()
{
    if [[ -e ansible_hosts ]]; then

        ini=($(cat ansible_hosts))
        idp_host_name=${ini[1]}

    else
        error_exit 'Error - Could not locate file "ansible_hosts"'
    fi
}

get_install_base ()
{
    ini=$(grep the_install_base= update_idp.sh)
    the_install_base=${ini#the_install_base=}
}

get_idp_settings ()
{
    host_vars_file="host_vars/$idp_host_name"

    if [[ -e $host_vars_file ]]; then

       ini=($(grep idp_entity_id: $host_vars_file))
       idp_entity_id=${ini[1]}
       idp_entity_id=${idp_entity_id//\"/}

       ini=($(grep idp_attribute_scope: $host_vars_file))
       idp_attribute_scope=${ini[1]}
       idp_attribute_scope=${idp_attribute_scope//\"/}

       ini=($(grep metadata_url: $host_vars_file))       
       metadata_url=${ini[1]}
       if [[ "$metadata_url" == *test* ]]; then
           environment=test
       else
           environment=production
       fi

       ini=($(grep organisation_name: $host_vars_file))
       unset ini[0]
       organisation_name=${ini[@]}

       ini=($(grep home_organisation: $host_vars_file))
       home_organisation=${ini[1]}
       home_organisation=${home_organisation//\"/}

       ini=($(grep home_organisation_type: $host_vars_file))
       home_organisation_type=${ini[1]}
       home_organisation_type=${home_organisation_type//\"/}

       ini=($(grep server_patch: $host_vars_file))
       server_patch=${ini[1]}
       server_patch=${server_patch//\"/}

       ini=($(grep firewall: $host_vars_file))
       firewall=${ini[1]}
       firewall=${firewall//\"/}
       if [[ "$firewall" == iptables ]]; then
          firewall=firewalld
       fi 

       ini=($(grep enable_backchannel: $host_vars_file))
       enable_backchannel=${ini[1]}
       enable_backchannel=${enable_backchannel//\"/}

       ini=($(grep enable_edugain: $host_vars_file))
       enable_edugain=${ini[1]}
       enable_edugain=${enable_edugain//\"/}

    else
       error_exit 'Error - Could not locate file "$host_vars_file"'
    fi
}

get_source_attr ()
{
    saml_file=assets/$idp_host_name/idp/conf/saml-nameid.properties

    ini=$(grep idp.persistentId.sourceAttribute $saml_file | grep -v "#")
    ini=${ini// /}
    source_attribute_id=${ini#*=}
}

get_ldap ()
{
    ldap_file=assets/$idp_host_name/idp/conf/ldap.properties

    ini=$(grep idp.authn.LDAP.ldapURL $ldap_file | grep -v %)
    ini=${ini// /}
    ldap_url=${ini#*=}

    ini=$(grep idp.authn.LDAP.baseDN $ldap_file | grep -v %)
    ini=${ini// /}
    ldap_base_dn=${ini#*=}

    ini=$(grep idp.authn.LDAP.bindDN $ldap_file | grep -v % | grep -v "#" | grep -v bindDNCredential)
    ini=${ini// /}
    ldap_bind_dn=${ini#*=}

    ini=$(grep idp.authn.LDAP.bindDNCredential $ldap_file | grep -v %)
    ini=${ini// /}
    ldap_bind_dn_password=${ini#*=}

    ini=$(grep idp.authn.LDAP.userFilter $ldap_file)
    ini=${ini// /}
    ini=${ini//(/}
    ini=${ini%=*}
    ldap_user_filter_attribute=${ini#*=}
}

write_bootstrap_ini ()
{
    bootstrap_file=$out_dir/bootstrap-v4.ini

    echo "# Bootstrap.ini file" > $bootstrap_file
    echo "#" >> $bootstrap_file
    echo "# Genereted by the upgrade_v4 tool on `date`" >> $bootstrap_file
    echo  >> $bootstrap_file
    echo "[main]" >> $bootstrap_file
    echo "HOST_NAME=$idp_host_name" >> $bootstrap_file
    echo "ENTITY_ID=$idp_entity_id" >> $bootstrap_file
    echo "IDP_SCOPE=$idp_attribute_scope" >> $bootstrap_file
    echo "ENVIRONMENT=$environment" >> $bootstrap_file
    echo "ORGANISATION_NAME=$organisation_name" >> $bootstrap_file
    echo "ORGANISATION_BASE_DOMAIN=$home_organisation" >> $bootstrap_file
    echo "HOME_ORG_TYPE=$home_organisation_type" >> $bootstrap_file
    echo "SOURCE_ATTRIBUTE_ID=$source_attribute_id" >> $bootstrap_file
    echo "PERSISTENT_ATTRIBUTE_ID=" >> $bootstrap_file
    echo "OS_UPDATE=$server_patch" >> $bootstrap_file
    
    echo >> $bootstrap_file
    echo "[ldap]" >> $bootstrap_file
    echo "LDAP_URL=$ldap_url" >> $bootstrap_file
    echo "LDAP_BASE_DN=$ldap_base_dn" >> $bootstrap_file
    echo "LDAP_BIND_DN=$ldap_bind_dn" >> $bootstrap_file
    echo "LDAP_BIND_DN_PASSWORD=$ldap_bind_dn_password" >> $bootstrap_file
    echo "LDAP_USER_FILTER_ATTRIBUTE=$ldap_user_filter_attribute" >> $bootstrap_file
    echo >> $bootstrap_file >> $bootstrap_file
    echo "[advanced]" >> $bootstrap_file
    echo "INSTALL_BASE=$the_install_base" >> $bootstrap_file
    echo "FIREWALL=$firewall" >> $bootstrap_file
    echo "ENABLE_EDUGAIN=$enable_edugain" >> $bootstrap_file
    echo "ENABLE_BACKCHANNEL=$enable_backchannel" >> $bootstrap_file
    echo "IDP_BEHIND_PROXY=false" >> $bootstrap_file
    echo "DEFAULT_ENCRYPTION=GCM" >> $bootstrap_file
}

copy_bilateral ()
{
    cp -r assets/$idp_host_name/idp/bilateral $out_dir
}

copy_credentials ()
{
    mkdir $out_dir/credentials
    cp assets/$idp_host_name/idp/credentials/*.crt $out_dir/credentials
    cp assets/$idp_host_name/idp/credentials/*.key $out_dir/credentials
    cp assets/$idp_host_name/idp/credentials/*.p12 $out_dir/credentials

    mkdir $out_dir/passwords
    cp passwords/$idp_host_name/aespt_salt $out_dir/passwords
    cp passwords/$idp_host_name/targeted_id_salt $out_dir/passwords
    cp passwords/$idp_host_name/shib_idp_keystore $out_dir/passwords
}

copy_web_certs ()
{
    mkdir $out_dir/tls
    cp assets/$idp_host_name/apache/server.crt $out_dir/tls
    cp assets/$idp_host_name/apache/server.key $out_dir/tls
    cp assets/$idp_host_name/apache/intermediate.crt $out_dir/tls
}

copy_config ()
{
    mkdir $out_dir/config
    cp assets/$idp_host_name/idp/conf/attribute-resolver.xml $out_dir/config
    cp assets/$idp_host_name/idp/conf/relying-party.xml $out_dir/config
    cp assets/$idp_host_name/idp/conf/services.xml $out_dir/config
    cp assets/$idp_host_name/idp/conf/metadata-providers.xml $out_dir/config
    cp assets/$idp_host_name/idp/conf/ldap.properties $out_dir/config
}

export_mysql ()
{
    mysqldump idp_db StorageRecords shibpid  tb_st --skip-add-drop-table --no-create-info > $out_dir/mysql-dump.sql
}


get_host_name

get_install_base

get_idp_settings

get_source_attr

get_ldap

create_output_dir

write_bootstrap_ini

copy_bilateral

copy_credentials

copy_web_certs

copy_config 

export_mysql
