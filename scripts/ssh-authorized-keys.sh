#!/bin/bash
#set -ex

# Script to manage SSH keys for IBM Cloud VPC Virtual Server Instances using Instance Metadata and IAM Trusted Profiles.
#
# (C) 2021 IBM
#
# Written by Dimitri Prosper, dimitri_prosper@us.ibm.com
#
#
#

# Exit on errors
# set -o errexit
# set -o pipefail
# set -o nounset

log_file=/var/log/ssh-authorized-keys.log
exec 3>&1 1>>$${log_file} 2>&1

function log_info {
  printf "$(date '+%Y-%m-%d %T') %s\n" "$@"
  printf "\e[1;34m$(date '+%Y-%m-%d %T') %s\e[0m\n" "$@" 1>&3
}

function log_success {
  printf "$(date '+%Y-%m-%d %T') %s\n" "$@"
  printf "\e[1;32m$(date '+%Y-%m-%d %T') %s\e[0m\n" "$@" 1>&3
}

function log_warning {
  printf "$(date '+%Y-%m-%d %T') %s\n" "$@"
  printf "\e[1;33m$(date '+%Y-%m-%d %T') %s\e[0m\n" "$@" 1>&3
}

function log_error {
  printf $(date '+%Y-%m-%d %T')" $@"
  printf >&2 "\e[1;31m$(date '+%Y-%m-%d %T') %s\e[0m\n" "$@" 1>&3
}

log_info "Verifying jq is installed and in the path."
type jq >/dev/null 2>&1 || { log_info "This script requires jq, but it's not installed."; exit 1; }

# Starting a continuous loop for refreshing authorized_keys
while [ true ]
do

  # Checking if Metatadata service is enabled.
  log_info "Checking if Metatadata service is enabled."
  nc -z -v -w5 169.254.169.254 80 >/dev/null 2>&1
  [ $? -ne 0 ] && log_error "The metadata service is not enabled" && exit 1

  # Calling the Instance Identity service to obtain the instance token.
  log_info "Getting instance identity access token."
  access_token_response=`curl --connect-timeout 5 -s -X PUT "http://169.254.169.254/instance_identity/v1/token?version=2021-10-12"\
    -H "Metadata-Flavor: ibm"\
    -H "Accept: application/json"\
    -d '{
          "expires_in": 3600
        }' > /tmp/access_token_response.json`
  
  # Validating response received.
  if [ -s /tmp/access_token_response.json ]; then
   if jq -e . /tmp/access_token_response.json >/dev/null 2>&1; then
      log_info "Received a valid json response from the Instance Identity service."
   else
      log_error "The response received from the Instance Identity service failed parsing as valid json."
      exit 1
   fi
  else
      log_error "The response received from the Instance Identity service call is empty, possibly metadata service is not enabled."
      exit 1
  fi

  # Parsing the access_token from the response.
  access_token=$(jq -r '(.access_token) | select (.!=null)' /tmp/access_token_response.json)
  if [ -z $${access_token} ]; then
    log_info "An access_token was not found in the response received from the Instance Identity service."
    exit 1
  fi

  # Calling the Instance Metadata service using the instance access_token.
  log_info "Getting instance metadata."
  curl -s -X GET "http://169.254.169.254/metadata/v1/instance?version=2021-09-10"\
    -H "Accept:application/json"\
    -H "Authorization: Bearer $${access_token}" > /tmp/instance.json

  # Validating response received from the Metadata service.
  if jq -e . /tmp/instance.json >/dev/null 2>&1; then
    log_info "Received a valid json response from the Metadata service."
  else
    log_error "The response received from the Metadata service failed parsing as valid json."
    exit 1
  fi

  # Parsing the zone, instance and instance_id from Metadata service response, inferring region from the zone.
  zone=$(jq -r '.zone.name | select (.!=null)' /tmp/instance.json)
  region=$(echo $${zone} | awk '{ print substr( $0, 1, length($0)-2 ) }')
  instance_name=$(jq -r '.name | select (.!=null)' /tmp/instance.json)
  instance_id=$(jq -r '.id | select (.!=null)' /tmp/instance.json)

  if [ ! -z $${region} ] && [ ! -z $${instance_name} ] && [ ! -z $${instance_id} ]; then
    # Calling the Instance Metadata service using the instance access_token and specifying the IAM trusted profile to use (profileid)
    # The profileid is supplied to the script from the Terraform template that was used to create it.
    log_info "Getting IAM token using profile_id ${profileid}."
    curl -s -X POST\
        -H "Content-Type: application/json"\
        -H "Accept: application/json"\
        -H "Authorization: Bearer $${access_token}"\
        -d '{"trusted_profile": {"id": "${profileid}" }}'\
        http://169.254.169.254/instance_identity/v1/iam_token?version=2021-10-12 > /tmp/iam_identity_token_response.json

    # Validating response received from the IAM service.
    if jq -e . /tmp/iam_identity_token_response.json >/dev/null 2>&1; then
      log_info "Received a valid json response from the Instance Metadata service."
    else
      log_error "The response received from the Instance Metadata service failed parsing as valid json."
      exit 1
    fi

    # Parsing the response received from IAM for errors.
    error_code=$(jq -r '.errors | select (.!=null)' /tmp/iam_identity_token_response.json)
    if [ -z $${error_code} ]; then

      # Parsing the response received from IAM for the instance iam_token.
      iam_token=$(jq -r '.access_token | select (.!=null)' /tmp/iam_identity_token_response.json)
      if [ ! -z $${iam_token} ]; then

        # Calling the regional VPC service to read SSH keys the instance is allowed to read based on its IAM identity.
        log_info "Getting list of SSH Keys authorized for $${instance_name} with id $${instance_id} in region $${region}."
        curl -s -X GET "https://$${region}.iaas.cloud.ibm.com/v1/keys?version=2021-09-07&generation=2" -H "Authorization: $${iam_token}" | jq '.keys' > /tmp/keys.json 
        
        # Validating response received from the IAM service.
        if jq -e . /tmp/keys.json >/dev/null 2>&1; then
          log_info "Received a valid json response from the regional VPC service."
        else
          log_error "The response received from the regional VPC service failed parsing as valid json."
          exit 1
        fi

        keys_count=$(jq length /tmp/keys.json)
        if [ $${keys_count} -eq 0 ]; then
          # If the instance is not allowed to read SSH keys, keys array count is equal to 0. Do not modify the authorized_keys.
          log_warning "No SSH keys found for $${instance_name} with id $${instance_id} in region $${region}, last saved authorized_keys is maintained."
        else
          # If the instance is allowed to read SSH keys, keys array count is greater than 0. reads all authorized keys and modify the authorized_keys.
          log_info "Found $${keys_count} SSH keys for $${instance_name} with id $${instance_id} in region $${region}."

          keys=$(jq -c '.[] | {id, name}' /tmp/keys.json)
          for key in $${keys}; do
            key_id=$(echo $${key} | jq -r '.id | select (.!=null)')
            key_name=$(echo $${key} | jq -r '.name | select (.!=null)')
            log_info "Writing SSH Key $${key_name} with id $${key_id} to authorized_keys."
          done

          jq -r '.[] | .public_key | gsub("[\\n]"; "")' /tmp/keys.json > ~/.ssh/authorized_keys

        fi
      fi
    else 
      log_error "Encountered error getting IAM token $${error_code}."
    fi
  fi
  # sleep for cyclewaitseconds, value provided by the Terraform template.
  sleep ${cyclewaitseconds}
done
exit 0