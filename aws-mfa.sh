#!/usr/bin/env bash

# log in with MFA

#############################
# GLOBALS
#############################

aws_mfa_cmd=$(basename $0)
profile='default'
token_code=''
action='login'
mfa_file="$HOME/.aws/mfa"
mfa_serial=''

#############################
# FUNCTIONS
#############################

die() {
  echo
  printf "$aws_mfa_cmd: %s\n" "$1" >&2
  usage
  exit 1
}

usage() {
  fold -s -w $(tput cols) <<EOT

==Usage==

To "login" (i.e. to export aws access env vars):

  eval "\$($aws_mfa_cmd [-p|--profile <aws_profile>] <-c token_code>)"

To "logout" (i.e. to unset aws access env vars):

  eval "\$($aws_mfa_cmd logout)"

You will need to save your MFA device's serial number in ${mfa_file}.  Profiles in ${mfa_file} are defined, similar to the config and credentials files.  Once you "login" with ${aws_mfa_cmd}, you don't need to specify --profile for other aws commands; the profile is implied by the credentials loaded in memory.

==Example contents of ${mfa_file}==

[default]
SN_OR_ARN_OF_MFA_DEVICE_FROM_default_PROFILE_ACCOUNT
[profile2]
SN_OR_ARN_OF_MFA_DEVICE_FROM_profile2_PROFILE_ACCOUNT
[profile3]
SN_OR_ARN_OF_MFA_DEVICE_FROM_profile3_PROFILE_ACCOUNT

EOT
}

load_mfa_serial() {
  mfa_serial=$(
    grep -A1 "^\s*\[$profile\]\s*$" $mfa_file | \
      tail -1 | sed -e 's/^\s*//' -e 's/\s*$//'
  )
}

parse_args() {
  local arg
  local expected_arg=''
  for arg in "$@"; do
    if [[ -z $expected_arg ]]; then
      case $arg in
        -p|--profile)   expected_arg='profile';;
        -c|--code)      expected_arg='token_code';;
        login|logout)   action=$arg;;
        *)              die "Invalid argument \"$arg\"";;
      esac
    else  # else expected_arg is defined
      case $expected_arg in
        profile)        profile=$arg;;
        token_code)     token_code=$arg;;
      esac
      expected_arg=''
    fi
  done
  if [[ $action == 'login' ]]; then
    if [[ -z $token_code ]]; then
      die "You must provide your MFA token's code with -c or --code"
    fi
  fi
}

echo_set_creds() {
  sts_cred_prefixes=(
    "export AWS_ACCESS_KEY_ID="
    "export AWS_SECRET_ACCESS_KEY="
    "export AWS_SESSION_TOKEN="
    "echo Token Expiration: "
  )
  local sts_results=(
    $(
      aws sts get-session-token \
        --profile $profile \
        --serial-number $mfa_serial \
        --token-code $token_code \
        --query '[ Credentials.AccessKeyId, Credentials.SecretAccessKey, Credentials.SessionToken, Credentials.Expiration ]' \
        --output text || echo "FAILED"
    )
  )
  if [[ $sts_results == 'FAILED' ]]; then
    die "Call to 'aws sts get-session-token' failed"
  else
    for i in $(seq 0 3); do
      echo ${sts_cred_prefixes[$i]}${sts_results[$i]}
    done
  fi
}

echo_unset_creds() {
  echo \
"unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
"
}

#############################
# MAIN PROGRAM
#############################

[[ -r $mfa_file ]] || die "I cannot access $mfa_file"
parse_args $@
load_mfa_serial
if [[ $action == 'login' ]]; then
  echo_set_creds
else
  echo_unset_creds
fi
