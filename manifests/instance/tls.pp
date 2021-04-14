# @summary Configure TLS for an instance
#
# Requires LDAPI to be enabled
#
# @author https://github.com/simp/pupmod-simp-ds389/graphs/contributors
#
define ds389::instance::tls (
  String[2]                                 $root_dn,
  Stdlib::Absolutepath                      $root_pw_file,
  Variant[Boolean, Enum['disabled','simp']] $ensure        = simplib::lookup('simp_options::pki', { 'default_value' => false}),
  Simplib::Port                             $port          = 636,
  String[1]                                 $source        = simplib::lookup('simp_options::pki', { 'default_value' => "/etc/pki/simp/${module_name}_${title}"}),
  Stdlib::Absolutepath                      $cert          = "/etc/pki/simp_apps/${module_name}_${title}/x509/public/${facts['fqdn']}.pub",
  Stdlib::Absolutepath                      $key           = "/etc/pki/simp_apps/${module_name}_${title}/x509/private/${facts['fqdn']}.pem",
  Stdlib::Absolutepath                      $cafile        = "/etc/pki/simp_apps/${module_name}_${title}/x509/cacerts/cacerts.pem",
  Ds389::ConfigItems                        $dse_config    = simplib::dlookup('ds389::instance::pki', 'dse_config', { 'default_value' => {} }),
  String[16]                                $token         = simplib::passgen("ds389_${title}_pki", { 'length' => 32 }),
  String[1]                                 $service_group = 'dirsrv'
) {
  assert_private()

  $_instance_name = split($title, /^(dirsrv@)?slapd-/)[-1]

  $_default_dse_config = {
    'cn=encryption,cn=config' => {
      'allowWeakCipher'               => 'off',
      'allowWeakDHParam'              => 'off',
      'nsSSL2'                        => 'off',
      'nsSSL3'                        => 'off',
      'nsSSLClientAuth'               => 'required',
      'nsTLS1'                        => 'on',
      'nsTLSAllowClientRenegotiation' => 'on',
      'sslVersionMax'                 => 'TLS1.2',
      'sslVersionMin'                 => 'TLS1.2'
    },
    'cn=config'               => {
      'nsslapd-ssl-check-hostname' => 'on',
      'nsslapd-validate-cert'      => 'on',
      'nsslapd-minssf'             => 256
    }
  }

  $_required_dse_config = {
    'cn=config' => {
      'nsslapd-security'   => 'on',
      'nsslapd-securePort' => $port
    }
  }

  if $ensure == 'disabled' {
    ds389::instance::attr::set { "Do not require encryption for ${_instance_name}":
      instance_name => $_instance_name,
      root_dn       => $root_dn,
      root_pw_file  => $root_pw_file,
      force_ldapi   => true,
      key           => 'nsslapd-minssf',
      value         => '0'
    }

    ds389::instance::selinux::port { "${port}":
      enable  => false,
      default => 636
    }
  }
  else {
    # Check to make sure we're not going to have a conflict with something that's running
    pick($facts['ds389__instances'], {}).each |$daemon, $data| {
      unless $daemon == $title {
        if $data['secure_port'] == $port {
          fail("The port '${port}' is already in use by '${daemon}'")
        }
      }
    }

    if defined_with_params(Ds389::Instance::Tls, { 'ensure' => $ensure, 'port' => $port }) {
      fail("The port '${port}' is already selected for use by another defined catalog resource")
    }

    ds389::instance::selinux::port { "${port}":
      instance => $title,
      default  => 636
    }

    $_pin_file = "/etc/dirsrv/slapd-${_instance_name}/pin.txt"
    $_token_file = "/etc/dirsrv/slapd-${_instance_name}/p12token.txt"

    file { $_pin_file:
      group   => $service_group,
      mode    => '0600',
      content => Sensitive("Internal (Software) Token:${token}\n")
    }

    file { $_token_file:
      mode    => '0400',
      content => Sensitive($token)
    }

    if $ensure {
      simplib::assert_optional_dependency($module_name, 'simp/pki')

      pki::copy { "${module_name}_${title}":
        source => $source,
        pki    => $ensure,
        group  => 'root',
        notify => Exec["Build ${_instance_name} p12"]
      }
    }

    $_instance_base = "/etc/dirsrv/slapd-${_instance_name}"
    $_p12_file = "${_instance_base}/puppet_import.p12"

    exec { "Validate ${_instance_name} p12":
      command => "rm -f ${_p12_file}",
      unless  => "openssl pkcs12 -nokeys -in ${_p12_file} -passin file:${_token_file}",
      path    => ['/bin', '/usr/bin'],
      notify  => Exec["Build ${_instance_name} p12"]
    }

    exec { "Build ${_instance_name} p12":
      command     => "openssl pkcs12 -export -name 'Server-Cert' -out ${_p12_file} -in ${key} -certfile ${cert} -passout file:${_token_file}",
      refreshonly => true,
      path        => ['/bin', '/usr/bin'],
      subscribe   => File[$_token_file]
    }

    exec { "Import ${_instance_name} p12":
      command   => "certutil -D -d ${_instance_base} -n 'Server-Cert' ||:; pk12util -i ${_p12_file} -d ${_instance_base} -w ${_token_file} -k ${_token_file} -n 'Server-Cert'",
      unless    => "certutil -d ${_instance_base} -L -n 'Server-Cert'",
      path      => ['/bin', '/usr/bin'],
      subscribe => Exec["Build ${_instance_name} p12"]
    }

    exec { "Import ${_instance_name} CA":
      command   => "certutil -D -d ${_instance_base} -n 'CA Certificate' ||:; certutil -A -i ${cafile} -d ${_instance_base} -n 'CA Certificate' -t 'CT,,' -a -f ${_token_file}",
      unless    => "certutil -d ${_instance_base} -L -n 'CA Certificate'",
      path      => ['/bin', '/usr/bin'],
      subscribe => Exec["Build ${_instance_name} p12"]
    }

    ds389::instance::dn::add { "RSA DN for ${_instance_name}":
      instance_name => $_instance_name,
      dn            => 'cn=RSA,cn=encryption,cn=config',
      objectclass   => [
        'top',
        'nsEncryptionModule'
      ],
      attrs         => {
        'nsSSLPersonalitySSL' => 'Server-Cert',
        'nsSSLActivation'     => 'on',
        'nsSSLToken'          => 'internal (software)'
      },
      root_dn       => $root_dn,
      root_pw_file  => $root_pw_file,
      force_ldapi   => true
    }

    ds389::instance::attr::set { "Configure PKI for ${_instance_name}":
      instance_name    => $_instance_name,
      root_dn          => $root_dn,
      root_pw_file     => $root_pw_file,
      attrs            => $_default_dse_config.deep_merge($dse_config).deep_merge($_required_dse_config),
      force_ldapi      => true,
      restart_instance => true,
      require          => Ds389::Instance::Dn::Add["RSA DN for ${_instance_name}"]
    }
  }
}
