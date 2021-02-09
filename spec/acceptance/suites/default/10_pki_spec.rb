# frozen_string_literal: true

require 'spec_helper_acceptance'

test_name '389DS with PKI'

describe '389DS with PKI' do
  let(:manifest) do
    'include ds389'
  end

  hosts_with_role(hosts, 'directory_server').each do |host|
    let(:ds_root_name) do
      'puppet_default'
    end
    let(:admin_password_file) do
      "/usr/share/puppet_ds389_config/#{ds_root_name}_ds_pw.txt"
    end

    fqdn = fact_on(host, 'fqdn').strip

    context 'when enabling PKI in the default instance' do
      let(:hieradata) do
        {
          'ds389::initialize_ds_root' => true,
          'ds389::bootstrap_ds_root_defaults' => true,
          'ds389::instance::default::enable_tls' => true,
          'ds389::instance::default::tls_params' => {
            'source' => '/etc/pki/simp-testing/pki'
          }
        }
      end

      it 'works with no errors' do
        set_hieradata_on(host, hieradata)
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'can not login to 389DS unencrypted' do
        expect { on(host, %(ldapsearch -x -y "#{admin_password_file}" -D "cn=Directory_Manager" -h #{fqdn} -b "cn=tasks,cn=config")) }.to raise_error(%r{.+})
      end

      it 'sets the environment variables for ldapsearch' do
        host.add_env_var('LDAPTLS_CACERT', '/etc/pki/simp_apps/ds389_puppet_default/x509/cacerts/cacerts.pem')
        host.add_env_var('LDAPTLS_KEY', "/etc/pki/simp_apps/ds389_puppet_default/x509/private/#{fqdn}.pem")
        host.add_env_var('LDAPTLS_CERT', "/etc/pki/simp_apps/ds389_puppet_default/x509/public/#{fqdn}.pub")
        host.add_env_var('LDAPTLS_CIPHER_SUITE', 'AES256-SHA256')
      end

      it 'can login to 389DS using STARTTLS' do
        on(host, %(ldapsearch -ZZ -x -y "#{admin_password_file}" -D "cn=Directory_Manager" -H ldap://#{fqdn}:389 -b "cn=tasks,cn=config"))
      end

      it 'can login to 389DS using LDAPS' do
        on(host, %(ldapsearch -x -y "#{admin_password_file}" -D "cn=Directory_Manager" -H ldaps://#{fqdn}:636 -b "cn=tasks,cn=config"))
      end

      it 'can login to 389DS via LDAPI' do
        on(host, %(ldapsearch -x -y "#{admin_password_file}" -D "cn=Directory_Manager" -H ldapi://%2fvar%2frun%2fslapd-#{ds_root_name}.socket -b "cn=tasks,cn=config"))
      end

      it 'unsets the environment variables for ldapsearch' do
        host.clear_env_var('LDAPTLS_CERT')
        host.clear_env_var('LDAPTLS_KEY')
        host.clear_env_var('LDAPTLS_CACERT')
        host.clear_env_var('LDAPTLS_CIPHER_SUITE')
      end
    end
  end
end
