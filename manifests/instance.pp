# @summary Set up a local 389DS server
#
# @param base_dn
#   The 'base' DN component of the directory server
#
# @param root_dn
#   The default administrator DN for the directory server
#
# @param admin_password
#   The password for the ``$admin_user`` and the ``$root_dn``
#
# @param listen_address
#   The IP address upon which to listen
#
# @param port
#   The port upon which to accept connections
#
# @param enable_admin_service
#   Enable the administrative interface for the GUI
#
# @param admin_user
#   The administrative user for administrative GUI connections
#
# @param admin_service_listen_address
#   The IP address upon which the administrative interface should listen
#
# @param admin_service_port
#   The port upon which the administrative interface should listen
#
# @param service_user
#   The user that ``389ds`` should run as
#
# @param service_group
#   The group that ``389ds`` should run as
#
# @param package_ensure
#   What to do regarding package installation
#
# @author https://github.com/simp/pupmod-simp-ds389/graphs/contributors
#
define ds389::instance (
  Enum['present','absent'] $ensure                       = 'present',
  Optional[String[2]]      $base_dn                      = undef,
  Optional[String[2]]      $root_dn                      = undef,
  Simplib::IP              $listen_address               = '127.0.0.1',
  Simplib::Port            $port                         = 389,
  Boolean                  $enable_admin_service         = false,
  String[2]                $admin_user                   = 'admin',
  Optional[String[2]]      $admin_password               = undef,
  Simplib::Domain          $admin_domain                 = $facts['domain'],
  Simplib::IP              $admin_service_listen_address = '0.0.0.0',
  Simplib::Port            $admin_service_port           = 9830,
  String[1]                $machine_name                 = $facts['fqdn'],
  String[1]                $service_user                 = 'nobody',
  String[1]                $service_group                = 'nobody',
  Optional[String[1]]      $ds_setup_ini_content         = undef,
  Stdlib::Absolutepath     $config_dir                   = '/usr/share/puppet_ds389_config',
  Simplib::PackageEnsure   $package_ensure               = simplib::lookup('simp_options::package_ensure', { 'default_value' => 'installed' })
) {
  simplib::assert_metadata($module_name)

  assert_type(Simplib::Systemd::ServiceName, $title) |$expected, $actual| {
    fail("The \$title for ds389::instance must be a valid systemd service name matching ${expected}. Got ${actual}")
  }

  if $title == 'admin' {
    fail('The 389DS server does not allow instances named "admin"')
  }

  if $title =~ /\.removed$/ {
    fail('You cannot end a 389DS instance with ".removed"')
  }

  if $ensure == 'present' {
    unless $base_dn {
      fail('You must specify a base_dn')
    }

    unless $root_dn {
      fail('You must specify a root_dn')
    }

    # Check to make sure we're not going to have a conflict with something that's running
    $_active_instance_ports = pick($facts['ds389__instances'], {}).map |$daemon, $data| {
      if $daemon == "slapd-${title}" {
        undef
      }
      else {
        $data['port']
      }
    }

    if $port in $_active_instance_ports {
      fail("The port '${port}' is already in use on '${facts["fqdn"]}'")
    }

    if defined_with_params(Ds389::Instance, { 'port' => $port }) {
      fail("The port '${port}' is already selected for use by another defined catalog resource")
    }

    # We need to include this here to make sure that all of the top-level
    # parameters propagate correctly downwards
    include ds389

    $_safe_path = simplib::safe_filename($title)

    if $admin_password {
      $_admin_password = $admin_password
    }
    else {
      $_admin_password = simplib::passgen("389-ds-${_safe_path}", { 'length' => 64, 'complexity' => 0 })
    }

    if $ds_setup_ini_content {
      $_ds_setup_inf = $ds_setup_ini_content
    }
    else {
      $_ds_setup_inf = @("DS_SETUP")
        # This file managed by Puppet
        [General]
        SuiteSpotUserID=${service_user}
        SuiteSpotGroup=${service_group}
        AdminDomain=${admin_domain}
        FullMachineName=${machine_name}
        ConfigDirectoryLdapURL=ldap://${facts['fqdn']}:${port}/o=NetscapeRoot
        ConfigDirectoryAdminID=${admin_user}
        ConfigDirectoryAdminPwd=${_admin_password}

        [slapd]
        ServerPort=${port}
        ServerIdentifier=${name}
        Suffix=${base_dn}
        RootDN=${root_dn}
        RootDNPwd=${_admin_password}
        SlapdConfigForMC=yes
        AddOrgEntries=yes
        AddSampleEntries=no

        [admin]
        Port=${admin_service_port}
        ServerAdminID=${admin_user}
        ServerAdminPwd=${_admin_password}
        ServerIpAddress=${admin_service_listen_address}
        | DS_SETUP
    }

    $_ds_config_file = "${config_dir}/ds_${$_safe_path}_setup.inf"

    file { $_ds_config_file:
      owner                   => 'root',
      group                   => 'root',
      mode                    => '0600',
      selinux_ignore_defaults => true,
      content                 => Sensitive($_ds_setup_inf),
      require                 => Class['ds389::install']
    }

    $_ds_instance_config = "/etc/dirsrv/slapd-${_safe_path}/dse.ldif"

    exec { "Setup ${title} DS":
      command => "${ds389::install::_setup_command} --silent -f ${_ds_config_file}",
      creates => $_ds_instance_config,
      require => File[$_ds_config_file],
      notify  => Service["dirsrv@${title}"]
    }

    ensure_resource('file', $config_dir,
      {
        ensure => 'directory',
        owner  => 'root',
        group  => 'root',
        mode   => '0640'
      }
    )

    $_ds_pw_file = "${config_dir}/${title}_ds_pw.txt"

    file { $_ds_pw_file:
      ensure  => 'present',
      owner   => 'root',
      group   => 'root',
      mode    => '0400',
      content => Sensitive($_admin_password),
      require => Exec["Setup ${title} DS"]
    }

    ensure_resource('service', "dirsrv@${title}",
      {
        ensure     => 'running',
        enable     => true,
        hasrestart => true
      }
    )

    ds389::config::item { "Set nsslapd-listenhost on ${title}":
      key             => 'nsslapd-listenhost',
      value           => $listen_address,
      admin_dn        => $root_dn,
      pw_file         => $_ds_pw_file,
      ds_host         => $listen_address,
      ds_port         => $port,
      ds_service_name => "dirsrv@${title}"
    }

    ds389::config::item { "Set nsslapd-securelistenhost on ${title}":
      key             => 'nsslapd-securelistenhost',
      value           => $listen_address,
      admin_dn        => $root_dn,
      pw_file         => $_ds_pw_file,
      ds_host         => $listen_address,
      ds_port         => $port,
      ds_service_name => "dirsrv@${title}"
    }
  }
  else {
    exec { "Remove 389DS instance ${title}":
      command => "/sbin/remove-ds.pl -f -i slapd-${title}",
      onlyif  => "/bin/test -d /etc/dirsrv/slapd-${title}"
    }
  }
}
