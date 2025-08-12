#!/bin/bash

# How to use
# ./update_staging.sh push
# ./update_staging.sh run
# ./update_staging.sh cleanup
# ./update_staging.sh cleanup --run-puppet

# List of staging pools and associated users
STAGING_POOLS=("gecko-t-osx-1100-m1-staging" "gecko-t-osx-1400-r8-staging" "gecko-t-osx-1500-m4-staging" "gecko-t-osx-1015-r8-staging")
RUN_USERS=("administrator" "relops" "administrator" "relops")

# Puppet config values
PUPPET_REPO="https://github.com/rcurranmoz/ronin_puppet.git"
PUPPET_BRANCH="cltbld_fix_again"
PUPPET_MAIL="rcurran@mozilla.com"

push_update() {
  for target in "${STAGING_POOLS[@]}"; do
    echo "Pushing update to $target..."
    bolt command run "mkdir -p /opt/puppet_environments && cat <<'EOF' > /opt/puppet_environments/ronin_settings
PUPPET_REPO='${PUPPET_REPO}'
PUPPET_BRANCH='${PUPPET_BRANCH}'
PUPPET_MAIL='${PUPPET_MAIL}'
EOF" \
      --targets "$target" \
      --run-as root \
      --no-host-key-check \
      --native-ssh
  done
}

run_puppet() {
  for i in "${!STAGING_POOLS[@]}"; do
    target="${STAGING_POOLS[$i]}"
    user="${RUN_USERS[$i]}"
    echo "Running puppet on $target as $user..."
    bolt command run "sudo /usr/local/bin/run-puppet.sh" \
      --targets "$target" \
      --run-as "$user" \
      --no-host-key-check \
      --native-ssh
  done
}

cleanup() {
  local run_after="$1"  # "yes" or empty

  for i in "${!STAGING_POOLS[@]}"; do
    target="${STAGING_POOLS[$i]}"
    user="${RUN_USERS[$i]}"
    echo "Removing ronin_settings from $target..."
    bolt command run "rm -f /opt/puppet_environments/ronin_settings" \
      --targets "$target" \
      --run-as root \
      --no-host-key-check \
      --native-ssh

    if [[ "$run_after" == "yes" ]]; then
      echo "Running puppet on $target as $user..."
      bolt command run "sudo /usr/local/bin/run-puppet.sh" \
        --targets "$target" \
        --run-as "$user" \
        --no-host-key-check \
        --native-ssh
    fi
  done
}

usage() {
  echo "Usage: $0 [push|run|cleanup [--run-puppet]]"
  exit 1
}

case "$1" in
  push) push_update ;;
  run) run_puppet ;;
  cleanup)
    if [[ "$2" == "--run-puppet" ]]; then
      cleanup yes
    else
      cleanup
    fi
    ;;
  *) usage ;;
esac
