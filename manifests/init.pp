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
# @param root_dn_password
#   The password for the the ``$root_dn``
#
#   * NOTE: To work around certain application bugs, items with spaces may not
#     be used in this field.
#
# @param listen_address
#   The IP address upon which to listen
#
# @param port
#   The port upon which to accept connections
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
class ds389 (
  Stdlib::Absolutepath         $config_dir                   = '/usr/share/puppet_ds389_config',
  Stdlib::Absolutepath         $ldif_working_dir             = "${config_dir}/ldifs",
  Boolean                      $initialize_ds_root           = false,
  Boolean                      $bootstrap_ds_root_defaults   = true,
  String[1]                    $ds_root_name                 = 'puppet_default',
  String[2]                    $base_dn                      = simplib::lookup('simp_options::ldap::base_dn', { 'default_value' => sprintf(simplib::ldap::domain_to_dn($facts['domain'], true)) }),
  Pattern['^[\S]+$']           $root_dn                      = 'cn=Directory_Manager',
  Simplib::IP                  $listen_address               = '0.0.0.0',
  Simplib::Port                $port                         = 389,
  Optional[Pattern['^[\S]+$']] $root_dn_password             = undef,
  String[1]                    $service_user                 = 'dirsrv',
  String[1]                    $service_group                = 'dirsrv',
  Hash                         $instances                    = {},
  Simplib::PackageEnsure       $package_ensure               = simplib::lookup('simp_options::package_ensure', { 'default_value' => 'installed' })
) {
  # WARNING: This is included by several defined types.
  # DO NOT add items here that will apply without being disabled by default.

  include ds389::install

  if $initialize_ds_root {
    $_default_instance_params = {
      port          => $port,
      service_user  => $service_user,
      service_group => $service_group
    }

    class { 'ds389::instance::default':
      base_dn                 => $base_dn,
      root_dn                 => $root_dn,
      instance_name           => $ds_root_name,
      bootstrap_with_defaults => $bootstrap_ds_root_defaults,
      listen_address          => $listen_address,
      instance_params         => $_default_instance_params
    }
  }

  file {
    [
      $config_dir,
      $ldif_working_dir
    ]:
    ensure  => 'directory',
    owner   => 'root',
    group   => $service_group,
    mode    => 'u+rwx,g+x,o-rwx',
    purge   => true,
    recurse => true
  }

  $instances.each |$id, $options| {
    ds389::instance { $id:
      * => $options
    }

    File[$ldif_working_dir] -> Ds389::Instance[$id]
  }
}
