#!/bin/bash

# Script used to configure the logging agent on IBM Cloud VPC Virtual Server Instances.
#
# (C) 2021 IBM
#
# Written by Dimitri Prosper, dimitri_prosper@us.ibm.com
#
#
#

name=log-agent-config
log_file=/var/log/$name.$(date +%Y%m%d_%H%M%S).log
exec 3>&1 1>>$log_file 2>&1

function log_info {
    printf "\e[1;34m$(date '+%Y-%m-%d %T') %s\e[0m\n" "$@" 1>&3
}

function log_success {
    printf "\e[1;32m$(date '+%Y-%m-%d %T') %s\e[0m\n" "$@" 1>&3
}

function log_warning {
    printf "\e[1;33m$(date '+%Y-%m-%d %T') %s\e[0m\n" "$@" 1>&3
}

function log_error {
    printf >&2 "\e[1;31m$(date '+%Y-%m-%d %T') %s\e[0m\n" "$@" 1>&3
}

function installTools {
    echo "deb ${logdna_agent_url} stable main" | tee /etc/apt/sources.list.d/logdna.list
    wget -O- ${logdna_agent_url}/logdna.gpg | apt-key add -

   log_info "Running apt update."
   export DEBIAN_FRONTEND=noninteractive
   apt update
   [ $? -ne 0 ] && echo "apt update command execution error." && return 1

   log_info "Running apt install linux-headers."
   apt install -y linux-headers-$(uname -r)
   [ $? -ne 0 ] && log_error "apt install command execution error." && return 1

   apt-get install logdna-agent < "/dev/null"
   logdna-agent -k ${logdna_agent_access_key}
   logdna-agent -s LOGDNA_APIHOST=${logdna_agent_api_host}
   logdna-agent -s LOGDNA_LOGHOST=${logdna_agent_log_host}
   logdna-agent -t ${logdna_agent_tags}
   update-rc.d logdna-agent defaults
   /etc/init.d/logdna-agent start

   return 0
}

function first_boot_setup {
    log_info "Started $name server configuration."

    installTools
    [ $? -ne 0 ] && log_error "installTools had errors." && exit 1

    return 0
}

first_boot_setup
[ $? -ne 0 ] && log_error "server setup had errors." && exit 1

exit 0