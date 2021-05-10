# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'sssd' do
  hosts.each do |host|
    let(:hieradata) do
      {
        'simp_options::pki'             => true,
        'simp_options::pki::source'     => '/etc/pki/simp-testing/pki',
        'simp_options::firewall'        => true,
        'simp_options::haveged'         => true,
        'simp_options::logrotate'       => true,
        'simp_options::pam'             => true,
        'simp_options::stunnel'         => true,
        'simp_options::syslog'          => true,
        'simp_options::tcpwrappers'     => true,
        'simp_options::ldap::uri'       => ['ldap://FIXME'],
        'simp_options::ldap::bind_dn'   => 'cn=hostAuth,ou=Hosts,dc=test,dc=case',
        'simp_options::ldap::base_dn'   => 'dc=test,dc=case',
        'simp_options::ldap::bind_pw'   => 'asouighoahgh3whg8arewhghaesdhgeahgoha',
        'simp_options::ldap::bind_hash' => '{SSHA}24M0TnXrhTsYzaaR+T4kDCKhu7dnVNBCG0qPMQ==',
        'sssd::domains'                 => ['LDAP'],
        'sssd::services'                => ['nss', 'pam', 'ssh'],
        # This causes a lot of noise and reboots
        'sssd::auditd'                  => false
      }
    end

    let(:fqdn) do
      fact_on(host,'fqdn').strip
    end

    let(:manifest) do
      <<~MANIFEST
        include '::sssd'
        include '::sssd::service::nss'
        include '::sssd::service::pam'
        include '::sssd::service::autofs'
        include '::sssd::service::sudo'
        include '::sssd::service::ssh'

        # LDAP CONFIG
        sssd::domain { 'LDAP':
          description       => 'LDAP Users Domain',
          id_provider       => 'ldap',
          auth_provider     => 'ldap',
          chpass_provider   => 'ldap',
          access_provider   => 'ldap',
          sudo_provider     => 'ldap',
          autofs_provider   => 'ldap',
          min_id            => 1000,
          enumerate         => false,
          cache_credentials => true,
          use_fully_qualified_names => false
        }
        sssd::provider::ldap { 'LDAP':
          ldap_pwd_policy => none,
          ldap_user_gecos => 'displayName',
          ldap_user_ssh_public_key => 'nsSshPublicKey',
          ldap_account_expire_policy => 'ipa',
          ldap_id_mapping => false,
          app_pki_key     => "/etc/pki/simp_apps/sssd/x509/private/#{fqdn}.pem",
          app_pki_cert    => "/etc/pki/simp_apps/sssd/x509/public/#{fqdn}.pub",
          ldap_default_authtok_type => 'password'
        }
      MANIFEST
    end

    dsidm_skip_message = "dsidm not found on #{host}"

    context 'when adding a test user' do
      let(:ldap_add_user) do
        <<~LDAP_ADD_USER
          dsidm puppet_default -b dc=test,dc=case posixgroup create --cn testuser --gidNumber 1001
          dsidm puppet_default -b dc=test,dc=case user create --cn testuser --uid testuser --displayName "Test User" --uidNumber 1001 --gidNumber 1001 --homeDirectory /home/testuser
          dsidm puppet_default -b dc=test,dc=case user modify testuser add:userPassword:{SSHA}NDZnXytV04X8JdhiN8zpcCE/r7Wrc9CiCukwtw==
          LDAP_ADD_USER
      end

      it 'adds an LDAP user' do
        if host.which('dsidm').empty?
          skip(dsidm_skip_message)
        else
          create_remote_file(host, '/tmp/ldap_add_user', ldap_add_user)
          on(host, 'chmod +x /tmp/ldap_add_user')
          on(host, '/tmp/ldap_add_user')
        end
      end
    end

    context 'when provided a valid sssd.conf' do
      it 'applies enough to generate sssd.conf' do
        if host.which('dsidm').empty?
          skip(dsidm_skip_message)
        else
          hieradata['simp_options::ldap::uri'] = ["ldap://#{fact_on(host, 'fqdn')}"]

          set_hieradata_on(host, hieradata)
          apply_manifest_on(host, manifest)
          # Allow it to flip the ldap_access_order since sssd is now installed
          apply_manifest_on(host, manifest)
        end
      end

      it 'is idempotent' do
        if host.which('dsidm').empty?
          skip(dsidm_skip_message)
        else
          apply_manifest_on(host, manifest, :catch_changes => true)
        end
      end

      it 'is running sssd' do
        if host.which('dsidm').empty?
          skip(dsidm_skip_message)
        else
          response = YAML.safe_load(on(host, %(puppet resource service sssd --to_yaml)).stdout.strip)
          expect(response['service']['sssd']['ensure']).to eq('running')
          expect(response['service']['sssd']['enable']).to eq('true')
        end
      end

      it 'can find testuser' do
        if host.which('dsidm').empty?
          skip(dsidm_skip_message)
        else
          expect(on(host, 'id testuser').output).to match (/1001/)
        end
      end
    end
  end
end
