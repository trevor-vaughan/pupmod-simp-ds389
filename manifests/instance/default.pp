# @summary Create a default instance with a common organizational LDIF
#
# @param instance_name
#   The unique name of this instance
#
# @param listen_address
#   The IP address upon which to listen
#
# @param bootstrap_with_defaults
#   Whether to use the inbuilt user/group directory structure
#
#   * If this is `true`, the traditional layout that the SIMP LDAP system has provided
#     will be used
#   * If this is `false`, the internal 389DS layout will be used
#     * NOTE: other SIMP module defaults may not work without alteration
#
# @param instance_params
#   Any other arguments that you wish to pass through directly to the
#   `ds389::instance` Defined Type.
#
# @author https://github.com/simp/pupmod-simp-ds389/graphs/contributors
#
class ds389::instance::default (
  String[1]                      $instance_name           = 'puppet_default',
  String[2]                      $base_dn                 = simplib::lookup('simp_options::ldap::base_dn', { 'default_value' => sprintf(simplib::ldap::domain_to_dn($facts['domain'], true)) }),
  String[2]                      $root_dn                 = 'cn=Directory_Manager',
  String[2]                      $bind_dn                 = simplib::lookup('simp_options::ldap::bind_dn', { 'default_value' => "cn=hostAuth,ou=Hosts,${base_dn}" }),
  String[1]                      $bind_pw                 = simplib::lookup('simp_options::ldap::bind_hash', { 'default_value' => simplib::passgen("ds389_${instance_name}_bindpw", {'length' => 64})}),
  Boolean                        $bootstrap_with_defaults = true,
  Simplib::IP                    $listen_address          = '0.0.0.0',
  Variant[Boolean, Enum['simp']] $enable_tls              = simplib::lookup('simp_options::pki', { 'default_value' => false }),
  Hash                           $tls_params              = {},
  Hash                           $instance_params         = {},

  # Default LDIF configuration parameters
  Integer[1]   $users_group_id                            = 100,
  Integer[500] $administrators_group_id                   = 700
) {
  assert_private()

  if $instance_params['ds_setup_ini_content'] {
    $_default_params = {
      'ds_setup_ini_content' => $instance_params['ds_setup_ini_content']
    }
  }
  elsif $instance_params['bootstrap_ldif_content'] {
    $_default_params = {
      'bootstrap_ldif_content' => $instance_params['bootstrap_ldif_content']
    }
  }
  elsif $bootstrap_with_defaults {
    $_default_params = {
      'bootstrap_ldif_content' => epp("${module_name}/instance/bootstrap.ldif.epp",
        {
          base_dn                 => $base_dn,
          root_dn                 => $root_dn,
          bind_dn                 => $bind_dn,
          bind_pw                 => $bind_pw,
          users_group_id          => $users_group_id,
          administrators_group_id => $administrators_group_id
        }
      )
    }
  }
  else {
    $_default_params = {}
  }

  ds389::instance { $instance_name:
    base_dn        => $base_dn,
    root_dn        => $root_dn,
    listen_address => $listen_address,
    enable_tls     => $enable_tls,
    tls_params     => $tls_params,
    *              => merge($_default_params, $instance_params)
  }
}
