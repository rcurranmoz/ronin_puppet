# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
define signing_worker (
  String $role,
  String $user,
  String $password,
  String $salt,
  String $iterations,
  String $scriptworker_base,
  String $dmg_prefix,
  String $cot_product,
  Array $supported_behaviors,
  String $keychain_filename,
  Hash $worker_config,
  Hash $role_config,
  Variant[String, Undef] $widevine_user = undef,
  Variant[String, Undef] $widevine_key = undef,
  Variant[String, Undef] $widevine_filename = undef,
  String $worker_type_prefix = '',
  String $worker_id_suffix = '',
  String $group = 'staff',
  Variant[String, Undef] $ed_key_filename = undef,
) {
  $virtualenv_dir           = "${scriptworker_base}/.venv"
  $certs_dir                = "${scriptworker_base}/certs"
  $requirements             = "${scriptworker_base}/requirements.txt"
  $scriptworker_config_file = "${scriptworker_base}/scriptworker.yaml"
  $script_config_file       = "${scriptworker_base}/script_config.yaml"
  $scriptworker_wrapper     = "${scriptworker_base}/scriptworker_wrapper.sh"
  $launchctl_wrapper        = "${scriptworker_base}/launchctl_wrapper.sh"
  $enable_scriptworker      = "${scriptworker_base}/enable_scriptworker.sh"

  # TODO: $worker_{id,type,group} only works with newer signers
  # Dep workers have a non-deterministic suffix
  if $facts['networking']['hostname'] =~ /.*-mac-v[34]-(dep)?signing(\d+).*/ {
    $worker_number = $2
  } else {
    $worker_number = 'unknown'
  }
  $worker_id = "${worker_type_prefix}${worker_config['worker_type']}-${worker_number}${worker_id_suffix}"
  $worker_type = "${worker_type_prefix}${worker_config['worker_type']}"
  $worker_group = $worker_type

  $ed_key_path = $ed_key_filename? {
    undef => '/dev/null',
    default => "${certs_dir}/${ed_key_filename}",
  }
  $widevine_cert_path = "${certs_dir}/${widevine_filename}"
  $keychain_path = "${certs_dir}/${keychain_filename}"

  signing_worker::system_user { "create_user_${user}":
    user       => $user,
    password   => $password,
    salt       => $salt,
    iterations => $iterations,
  }

  $required_directories = [
    $scriptworker_base,
    "${scriptworker_base}/logs",
  ]
  file { $required_directories:
    ensure => 'directory',
    owner  => $user,
    group  => $group,
    mode   => '0750',
  }
  file { "${scriptworker_base}/certs":
    ensure => 'directory',
    owner  => $user,
    group  => $group,
    mode   => '0700',
  }

  $tc_scope_prefix = $cot_product ? {
    'firefox' => $worker_config['ff_taskcluster_scope_prefix'],
    'thunderbird' => $worker_config['tb_taskcluster_scope_prefix'],
    'mozillavpn' => $worker_config['vpn_taskcluster_scope_prefix'],
    'adhoc' => $worker_config['adhoc_taskcluster_scope_prefix'],
  }
  $tc_client_id = $cot_product ? {
    'firefox' => $worker_config['ff_taskcluster_client_id'],
    'thunderbird' => $worker_config['tb_taskcluster_client_id'],
    'mozillavpn' => $worker_config['vpn_taskcluster_client_id'],
    'adhoc' => $worker_config['adhoc_taskcluster_client_id'],
  }
  $tc_access_token = $cot_product ? {
    'firefox' => $worker_config['ff_taskcluster_access_token'],
    'thunderbird' => $worker_config['tb_taskcluster_access_token'],
    'mozillavpn' => $worker_config['vpn_taskcluster_access_token'],
    'adhoc' => $worker_config['adhoc_taskcluster_access_token'],
  }

  # TODO: Remove this once the new virtualenvs (.venv) have been deployed
  file { "${scriptworker_base}/virtualenv":
    ensure    => 'absent',
    recurse   => true,
    purge     => true,
    force     => true,
    max_files => 100000,
  }

  # Setting up the virtualenv happens in 3 stages:
  # 1) Create it
  # 2) Clone the scriptworker-scripts repo
  # 3) Install iscript and its dependencies
  $scriptworker_scripts_clone_dir = "${scriptworker_base}/scriptworker-scripts"

  exec { "install ${scriptworker_base} virtualenv":
    command => 'uv venv',
    cwd     => $scriptworker_base,
    user    => $user,
    group   => $group,
    onlyif  => 'test ! -f .venv/bin/activate',
    path    => ['/usr/local/bin', '/bin', '/usr/sbin'],
  }

  vcsrepo { $scriptworker_scripts_clone_dir:
    ensure   => latest,
    provider => git,
    source   => 'https://github.com/mozilla-releng/scriptworker-scripts',
    revision => $worker_config['scriptworker_scripts_revision'],
    user     => $user,
    group    => $group,
    require  => File[$scriptworker_base],
  }
  $ss_deps = [
    Vcsrepo[$scriptworker_scripts_clone_dir],
    Exec["install ${scriptworker_base} virtualenv"],
  ]
  exec { "install ${scriptworker_base} iscript":
    command     => 'uv sync --active --locked --inexact --package iscript --extra scriptworker',
    cwd         => $scriptworker_scripts_clone_dir,
    environment => [
      "VIRTUAL_ENV=${scriptworker_base}/.venv",
    ],
    user        => $user,
    group       => $group,
    refreshonly => true,
    subscribe   => $ss_deps,
    require     => $ss_deps,
    path        => ['/usr/local/bin', '/bin', '/usr/sbin'],
  }

  if $widevine_filename {
    $widevine_clone_dir = "${scriptworker_base}/widevine"

    file { $widevine_clone_dir:
      ensure => 'directory',
      owner  => $user,
      group  => $group,
      mode   => '0755',
      before => Exec["clone widevine ${scriptworker_base}"],
    }

    # We only clone this once for three reasons:
    # 1) It is almost never updated
    # 2) We don't support general code deployments through puppet (yet)
    # 3) The clone url contains a github token, which we don't want sitting around on disk
    #
    # In an ideal world we'd still use `vcsrepo` for this, but it breaks after we
    # clean up the token, so we're stuck with this for now.
    exec { "clone widevine ${scriptworker_base}":
      command => "git clone https://${widevine_user}:${widevine_key}@github.com/mozilla-services/widevine ${widevine_clone_dir}",
      cwd     => $scriptworker_base,  # new
      user    => $user,
      group   => $group,
      unless  => "test -d ${widevine_clone_dir}/src",
      path    => ['/bin', '/usr/bin'],
      require => [File[$scriptworker_base], File[$widevine_clone_dir]],
    }
    # This has credentials in it. Clean up.
    ->file { "Remove widevine directory ${scriptworker_base}":
      ensure  => absent,
      path    => "${widevine_clone_dir}/.git",
      recurse => true,
      purge   => true,
      force   => true,
    }
    exec { "install ${scriptworker_base} widevine":
      command     => 'uv pip install .',
      cwd         => $widevine_clone_dir,
      environment => [
        "VIRTUAL_ENV=${scriptworker_base}/.venv",
      ],
      user        => $user,
      group       => $group,
      refreshonly => true,
      subscribe   => [Exec["clone widevine ${scriptworker_base}"], Exec["install ${scriptworker_base} virtualenv"]],
      require     => [Exec["clone widevine ${scriptworker_base}"], Exec["install ${scriptworker_base} virtualenv"]],
      path        => ['/usr/local/bin', '/bin', '/usr/sbin'],
    }
  }

  # XXX once we:
  #     - get the virtualenv to re-run pip on requirements.txt change,
  #     - get the scriptworker to restart on config or python change, and
  #     - get puppet running periodically,
  #     we can upgrade scriptworker and python deps without sshing in.

  # scriptworker config
  file { $script_config_file:
    content => template('signing_worker/script_config.yaml.erb'),
    owner   => $user,
    group   => $group,
    mode    => '0400',
  }
  file { $scriptworker_config_file:
    content => template('signing_worker/scriptworker.yaml.erb'),
    owner   => $user,
    group   => $group,
    mode    => '0400',
  }

  file { $scriptworker_wrapper:
    content => template('signing_worker/scriptworker_wrapper.sh.erb'),
    mode    => '0700',
    owner   => $user,
    group   => $group,
  }

  $launchd_script_name = "org.mozilla.scriptworker.${user}"
  $launchd_script = "/Library/LaunchDaemons/${launchd_script_name}.plist"
  file { $launchd_script:
    content => template('signing_worker/org.mozilla.scriptworker.plist.erb'),
    mode    => '0644',
  }
  file { $launchctl_wrapper:
    content => template('signing_worker/launchctl_wrapper.sh.erb'),
    mode    => '0755',
    owner   => $user,
    group   => $group,
  }
  file { $enable_scriptworker:
    content => template('signing_worker/enable_scriptworker.sh.erb'),
    mode    => '0755',
    owner   => $user,
    group   => $group,
  }
  exec { "${user}_launchctl_load":
    command     => "/bin/bash ${$launchctl_wrapper}",
    refreshonly => true,
    subscribe   => [
      Exec["install ${scriptworker_base} iscript"],
      File[$launchd_script],
      File[$launchctl_wrapper],
      File[$scriptworker_config_file],
      File[$scriptworker_wrapper],
    ],
  }
}
