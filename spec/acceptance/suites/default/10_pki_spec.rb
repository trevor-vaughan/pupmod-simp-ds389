# frozen_string_literal: true

require 'spec_helper_acceptance'

test_name '389DS with PKI'

describe '389DS with PKI' do
  let(:manifest) do
    'include ds389'
  end

  hosts_with_role(hosts, 'directory_server').each do |host|
    context "on #{host} " do
      let(:ds_root_name) { 'test_tls' }
      let(:base_dn) { 'dc=tls,dc=com' }
      let(:rootpasswd) { 'password'}
      let(:root_dn) { 'cn=Directory_Manager' }
      let(:bootstrapldif) { ERB.new(File.read(File.expand_path('files/bootstrap.ldif.erb',File.dirname(__FILE__)))).result(binding) }
      let(:fqdn) {  fact_on(host, 'fqdn').strip }
      let(:certdir) {'/etc/pki/simp-testing/pki'}

      let(:root_dn_password_file) do
        "/usr/share/puppet_ds389_config/#{ds_root_name}_ds_pw.txt"
      end
      let(:hieradata) do
        {
          'ds389::instances'  => {
            ds_root_name => {
              'base_dn' => "#{base_dn}",
              'root_dn' => "#{root_dn}",
              'root_dn_password' => "#{rootpasswd}",
              'listen_address' => '0.0.0.0',
              'enable_tls' => true,
              'tls_params' => {
                'source' => "#{certdir}"
              },
            }
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
        expect { on(host, %(ldapsearch -x -w "#{rootpasswd}" -D "#{root_dn}" -h #{fqdn} -b "cn=tasks,cn=config")) }.to raise_error(%r{.+})
      end

      it 'sets the environment variables for ldapsearch' do
        host.add_env_var('LDAPTLS_CACERT', "#{certdir}/cacerts/cacerts.pem")
        host.add_env_var('LDAPTLS_KEY', "#{certdir}/private/#{fqdn}.pem")
        host.add_env_var('LDAPTLS_CERT', "#{certdir}/public/#{fqdn}.pub")
      end

      it 'can login to 389DS using STARTTLS' do
        on(host, %(ldapsearch -ZZ -x -w "#{rootpasswd}" -D "#{root_dn}" -H ldap://#{fqdn}:389 -b "cn=tasks,cn=config"))
      end

      it 'can login to 389DS using LDAPS' do
        on(host, %(ldapsearch -x -w "#{rootpasswd}" -D "#{root_dn}" -H ldaps://#{fqdn}:636 -b "cn=tasks,cn=config"))
      end

      it 'can login to 389DS via LDAPI' do
        on(host, %(ldapsearch -x -w "#{rootpasswd}" -D "#{root_dn}" -H ldapi://%2fvar%2frun%2fslapd-#{ds_root_name}.socket -b "cn=tasks,cn=config"))
      end

      it 'unsets the environment variables for ldapsearch' do
        host.clear_env_var('LDAPTLS_CERT')
        host.clear_env_var('LDAPTLS_KEY')
        host.clear_env_var('LDAPTLS_CACERT')
      end
    end
  end
end
