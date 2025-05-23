# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# NOTE(aerickson): please don't add more global variables.
#   variables like this should be set in profile modules.
#   these make testing difficult (this block must be
#   copy/pasted into every puppet-kitchen manifests).
case $facts['os']['name'] {
    'Windows': {
    }
    'Darwin': {
        # Set toplevel variables for Darwin
        $root_user  = 'root'
        $root_group = 'wheel'

    }
    'Ubuntu': {
        $root_user = 'root'
        $root_group = 'root'
    }
    default: {
    }
}

# Role-based classification using puppet_role fact
if $facts['puppet_role'] {
  case $facts['puppet_role'] {
    'gecko_t_osx_1400_r8_staging': {
      include ::roles_profiles::roles::gecko_t_osx_1400_r8_staging
    }
    'mozilla_b_1_osx': {
      include ::roles_profiles::roles::mozilla_b_1_osx
    }
    default: {
      fail("Unknown puppet_role: ${facts['puppet_role']}")
    }
  }
} else {
  fail('No puppet_role fact provided. Cannot classify node.')
}

# node /vagrantup.com/ {
#     # ok, no need to fail
# }

# Default node should always fail
node default {
#   fail("Missing node classification for current host (node '${networking['fqdn']}')!")
}
