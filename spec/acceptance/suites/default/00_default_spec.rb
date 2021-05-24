# frozen_string_literal: true

require 'spec_helper_acceptance'

test_name 'Set up 389DS'

describe 'Set up 389DS' do
  let(:manifest) do
    'include ds389'
  end

  unless hosts.find { |h| h[:hypervisor] == 'docker' }
    hosts.each do |host|
      context "on #{host}" do
        it 'has a proper FQDN' do
          on(host, "hostname #{fact_on(host, 'fqdn')}")
          on(host, 'hostname -f > /etc/hostname')
        end
      end
    end
  end

  hosts_with_role(hosts, 'directory_server').each do |host|

    context 'with default setup' do
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'is not running any slapd instances' do
        expect(on(host, 'ls /etc/dirsrv/slapd-*', accept_all_exit_codes: true).stdout.strip).to be_empty
      end
    end


    context 'create an instance' do
      let(:base_dn) { 'dc=test,dc=com' }
      let(:rootpasswd) { 'password'}
      let(:root_dn) { 'cn=Directory_Manager' }
      let(:root_dn_pwd) { on(host, "/usr/bin/pwdhash -s SHA256 #{rootpasswd}").output.strip }
      let(:bootstrapldif) { ERB.new(File.read(File.expand_path('files/bootstrap.ldif.erb',File.dirname(__FILE__)))).result(binding) }
      let(:ds_root_name) { 'test_in'}

      let(:manifest) { <<-EOM
          ds389::instance { "#{ds_root_name}":
            base_dn                => '#{base_dn}',
            root_dn                => '#{root_dn}',
            root_dn_password       => '#{rootpasswd}',
            bootstrap_ldif_content => '#{bootstrapldif}',
            enable_tls             => false
            }
      EOM
      }


      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'is running ns-slapd' do
        apply_manifest_on(host, 'package { "iproute": ensure => installed }')
        on(host, 'ps -u dirsrv')
        on(host, 'ss -tlpn | grep :389')
      end

      it 'can login to 389DS' do
        on(host, %(ldapsearch -x -w "#{rootpasswd}" -D "#{root_dn}" -h localhost -b "cn=tasks,cn=config"))
      end

      it 'can login to 389DS via LDAPI' do
        on(host, %(ldapsearch -x -w "#{rootpasswd}" -D "#{root_dn}" -H ldapi://%2fvar%2frun%2fslapd-#{ds_root_name}.socket -b "cn=tasks,cn=config"))
      end

      it 'contains the entries from the ldif' do

        result = on(host, %(ldapsearch -x -w "#{rootpasswd}" -D "#{root_dn}" -H ldapi://%2fvar%2frun%2fslapd-#{ds_root_name}.socket -b "#{base_dn}")).output

        expect(result.lines.grep(%r{cn=administrators,ou=Group,#{base_dn}})).not_to be_empty
      end

      it 'fails when logging in with forced encryption' do
        expect { on(host, %(ldapsearch -ZZ -x -w "#{rootpasswd}" -D "#{root_dn}" -h `hostname -f` -b "cn=tasks,cn=config")) }.to raise_error(Beaker::Host::CommandFailure)
      end
    end

    context 'with an instance to delete' do
      # Let passgen auto generate the password and get the password from the file.
      let(:root_dn_password_file) do
        "/usr/share/puppet_ds389_config/#{ds_root_name}_ds_pw.txt"
      end

      let(:ds_root_name) { 'scrap' }
      let(:hieradata) do
        {
          'ds389::instances'                     => {
            ds_root_name => {
              'base_dn' => 'dc=scrap test,dc=space',
              'root_dn' => 'cn=Scrap_Admin',
              'listen_address' => '0.0.0.0',
              'port' => 388
            }
          }
        }
      end

      it 'enables the instance' do
        set_hieradata_on(host, hieradata)
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'can login to 389DS' do
        # rubocop:disable Layout/LineLength
        on(host, %(ldapsearch -x -y "#{root_dn_password_file}" -D "#{hieradata['ds389::instances'][ds_root_name]['root_dn']}" -H ldapi://%2fvar%2frun%2fslapd-#{ds_root_name}.socket -b "cn=tasks,cn=config"))
        # rubocop:enable Layout/LineLength
      end
    end

    context 'when removing a server instance' do
      let(:manifest) do
        <<~MANIFEST
          ds389::instance { "scrap": ensure => "absent" }
          ds389::instance { "test_in": ensure => "absent" }
          MANIFEST
      end
      let(:hieradata) do
        { 'ds389::initialize_ds_root' => true }
      end

      it 'clears the hieradata' do
        set_hieradata_on(host, hieradata)
      end

      it 'removes the server instance' do
        expect(directory_exists_on(host, '/etc/dirsrv/slapd-scrap')).to be true
        expect(directory_exists_on(host, '/etc/dirsrv/slapd-test_in')).to be true

        apply_manifest_on(host, manifest, catch_failures: true)

        expect(directory_exists_on(host, '/etc/dirsrv/slapd-scrap')).to be false
        expect(directory_exists_on(host, '/etc/dirsrv/slapd-test_in')).to be false
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end
    end
  end
end
