# @summary Set up a local 389DS server
#
# @param base_dn
#   The 'base' DN component of the directory server
#
# @param root_dn
#   The default administrator DN for the directory server
#
#   * NOTE: To work around certain application bugs, items with spaces may not
#     be used in this field.
#
# @param admin_password
#   The password for the ``$admin_user`` and the ``$root_dn``
#
#   * NOTE: To work around certain application bugs, items with spaces may not
#     be used in this field.
#
# @param listen_address
#   The IP address upon which to listen
#
# @param port
#   The port upon which to accept normal/STARTTLS connections
#
# @param secure_port
#   The port upon which to accept LDAPS connections
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
# @param bootstrap_ldif_content
#   The content that should be used to initialize the directory
#
# @param general_config
#   General configuration items for the instance
#
#   * These items fall under the `cn=config` root and will take precedence over
#     any conflicting, more specific, Hashes
#
# @param package_ensure
#   What to do regarding package installation
#
# @author https://github.com/simp/pupmod-simp-ds389/graphs/contributors
#
define ds389::instance (
  Enum['present','absent']     $ensure                       = 'present',
  Optional[String[2]]          $base_dn                      = undef,
  Optional[Pattern['^[\S]+$']] $root_dn                      = undef,
  Simplib::IP                  $listen_address               = '127.0.0.1',
  Simplib::Port                $port                         = 389,
  Simplib::Port                $secure_port                  = 636,
  Boolean                      $enable_admin_service         = false,
  String[2]                    $admin_user                   = 'admin',
  Optional[Pattern['^[\S]+$']] $admin_password               = undef,
  Simplib::Domain              $admin_domain                 = $facts['domain'],
  Simplib::IP                  $admin_service_listen_address = '127.0.0.1',
  Simplib::Port                $admin_service_port           = 9830,
  String[1]                    $machine_name                 = $facts['fqdn'],
  String[1]                    $service_user                 = 'dirsrv',
  String[1]                    $service_group                = 'dirsrv',
  Optional[String[1]]          $bootstrap_ldif_content       = undef,
  Optional[String[1]]          $ds_setup_ini_content         = undef,
  Ds389::ConfigItem            $general_config               = simplib::dlookup('ds389::instance', 'general_config', {'default_value' => {} }),
  Boolean                      $enable_tls                   = simplib::lookup('simp_options::pki', { 'default_value' => false }),
  Hash                         $tls_params                   = simplib::dlookup('ds389::instance', 'tls_params', { 'default_value' => {} }),
  Simplib::PackageEnsure       $package_ensure               = simplib::lookup('simp_options::package_ensure', { 'default_value' => 'installed' })
) {
  simplib::assert_metadata($module_name)

  assert_type(Simplib::Systemd::ServiceName, $title) |$expected, $actual| {
    fail("The \$title for ds389::instance must be a valid systemd service name matching ${expected}. Got ${actual}")
  }
  if stdlib::start_with($title, 'dirsrv@') or stdlib::start_with($title, 'slapd-') {
    fail('The $title for ds389::instance cannot start with "dirsrv@" or "slapd-"')
  }
  if $title == 'admin' {
    fail('The 389DS server does not allow instances named "admin"')
  }
  if stdlib::end_with($title, '.removed') {
    fail('You cannot end a 389DS instance with ".removed"')
  }

  $_ds_remove_command = "/sbin/remove-ds.pl -f -i slapd-${title}"

  if $ensure == 'present' {
    unless $base_dn { fail('You must specify a base_dn') }
    unless $root_dn { fail('You must specify a root_dn') }

    # Check to make sure we're not going to have a conflict with something that's running
    pick($facts['ds389__instances'], {}).each |$daemon, $data| {
      unless $daemon == $title {
        if $data['port'] == $port {
          fail("The port '${port}' is already in use by '${daemon}'")
        }
      }
    }

    if defined_with_params(Ds389::Instance, { 'ensure' => $ensure, 'port' => $port }) {
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
      if $bootstrap_ldif_content {
        $_bootstrap_ldif_file = "${ds389::config_dir}/${_safe_path}_ds_bootstrap.ldif"

        file { $_bootstrap_ldif_file:
          owner   => 'root',
          group   => $service_group,
          mode    => '0640',
          content => Sensitive($bootstrap_ldif_content),
          notify  => Exec["Setup ${title} DS"]
        }
      }
      else {
        $_bootstrap_ldif_file = undef
      }

      $_ds_setup_inf = epp("${module_name}/instance/setup.ini.epp",
        {
          server_identifier            => $title,
          base_dn                      => $base_dn,
          root_dn                      => $root_dn,
          service_user                 => $service_user,
          service_group                => $service_group,
          machine_name                 => $machine_name,
          port                         => $port,
          admin_user                   => $admin_user,
          admin_password               => $_admin_password,
          admin_domain                 => $admin_domain,
          admin_service_listen_address => $admin_service_listen_address,
          admin_service_port           => $admin_service_port,
          bootstrap_ldif_file          => $_bootstrap_ldif_file
        }
      )
    }

    ds389::instance::selinux::port { $port:
      $default => 389,
      before    => [
        Ds389::Instance::Service[$title],
        Exec["Setup ${title} DS"]
      ]
    }

    $_ds_config_file = "${ds389::config_dir}/${$_safe_path}_ds_setup.inf"

    file { $_ds_config_file:
      owner                   => 'root',
      group                   => 'root',
      mode                    => '0600',
      selinux_ignore_defaults => true,
      content                 => Sensitive($_ds_setup_inf),
      require                 => Class['ds389::install'],
      notify                  => Exec["Setup ${title} DS"]
    }

    $_ds_instance_config = "/etc/dirsrv/slapd-${_safe_path}/dse.ldif"

    if $enable_admin_service {
      $_setup_command = $ds389::install::admin_setup_command

      # Newer versions don't have this file so we need to make a passthrough
      file { $_setup_command:
        target  => $ds389::install::setup_command,
        replace => false,
        before  => Exec["Setup ${title} DS"]
      }
    }
    else {
      $_setup_command = $ds389::install::setup_command
    }

    exec { "Setup ${title} DS":
      command => "${_setup_command} --silent -f ${_ds_config_file}",
      creates => $_ds_instance_config,
      notify  => Ds389::Instance::Service[$title]
    }

    $_ds_pw_file = "${ds389::config_dir}/${_safe_path}_ds_pw.txt"

    file { $_ds_pw_file:
      ensure  => 'present',
      owner   => 'root',
      group   => 'root',
      mode    => '0400',
      content => Sensitive($_admin_password),
      require => Exec["Setup ${title} DS"]
    }

    ensure_resource('ds389::instance::service', $title)

    # This needs to happen first so that we can skip through to ldapi afterwards
    ds389::instance::attr::set { "Configure LDAPI for ${title}":
      instance_name => $title,
      attrs         => {
        'cn=config' => {
          'nsslapd-ldapilisten' => 'on',
          'nsslapd-localssf'    => 99999
        }
      },
      root_dn          => $root_dn,
      root_pw_file     => $_ds_pw_file,
      host             => $listen_address,
      port             => $port,
      restart_instance => true
    }

    $_dse_config = {
      'cn=config' => {
        'nsslapd-listenhost'       => $listen_address,
        'nsslapd-securelistenhost' => $listen_address
      }.merge($general_config)
    }
    ds389::instance::attr::set { "Core configuration for ${title}":
      instance_name => $title,
      attrs         => $_dse_config,
      root_dn       => $root_dn,
      root_pw_file  => $_ds_pw_file,
      force_ldapi   => true,
      require       => Ds389::Instance::Attr::Set["Configure LDAPI for ${title}"]
    }

    if $enable_tls {
      ds389::instance::tls { $title:
        ensure        => $enable_tls,
        root_dn       => $root_dn,
        root_pw_file  => $_ds_pw_file,
        port          => $secure_port,
        service_group => $service_group,
        *             => $tls_params,
        require       => Ds389::Instance::Attr::Set["Configure LDAPI for ${title}"]
      }
    }
  }
  else {
    exec { "Remove 389DS instance ${title}":
      command => $_ds_remove_command,
      onlyif  => "/bin/test -d /etc/dirsrv/slapd-${title}"
    }

    ds389::instance::selinux::port { $port:
      enable  => false,
      default => 389
    }
    ds389::instance::selinux::port { $secure_port:
      enable  => false,
      default => 636
    }
  }
}
