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
    let(:ds_root_name) { 'puppet_default' }
    let(:admin_password_file) do
      "/usr/share/puppet_ds389_config/#{ds_root_name}_ds_pw.txt"
    end

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

    context 'when creating the default instance' do
      let(:hieradata) do
        {
          'ds389::initialize_ds_root' => true,
          'ds389::bootstrap_ds_root_defaults' => true
        }
      end

      it 'works with no errors' do
        set_hieradata_on(host, hieradata)
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
        on(host, %(ldapsearch -x -y "#{admin_password_file}" -D "cn=Directory_Manager" -h localhost -b "cn=tasks,cn=config"))
      end

      it 'can login to 389DS via LDAPI' do
        on(host, %(ldapsearch -x -y "#{admin_password_file}" -D "cn=Directory_Manager" -H ldapi://%2fvar%2frun%2fslapd-#{ds_root_name}.socket -b "cn=tasks,cn=config"))
      end

      it 'contains the default entries' do
        domain = on(host, %(puppet apply --color=none -e '$dn = simplib::ldap::domain_to_dn($facts["domain"], true); notice("DOMAIN => ${dn}")'))
                 .stdout
                 .lines
                 .grep(%r{DOMAIN =>})
                 .first
                 .split('=> ')
                 .last
                 .strip

        result = on(host, %(ldapsearch -x -y "#{admin_password_file}" -D "cn=Directory_Manager" -H ldapi://%2fvar%2frun%2fslapd-#{ds_root_name}.socket -b "#{domain}")).output

        expect(result.lines.grep(%r{cn=administrators,ou=Group,#{domain}})).not_to be_empty
      end

      it 'fails when logging in with forced encryption' do
        expect { on(host, %(ldapsearch -ZZ -x -y "#{admin_password_file}" -D "cn=Directory_Manager" -h `hostname -f` -b "cn=tasks,cn=config")) }.to raise_error(Beaker::Host::CommandFailure)
      end
    end

    context 'with an instance to delete' do
      let(:ds_root_name) { 'scrap' }
      let(:hieradata) do
        {
          'ds389::initialize_ds_root' => true,
          'ds389::instances' => {
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
        on(host, %(ldapsearch -x -y "#{admin_password_file}" -D "#{hieradata['ds389::instances'][ds_root_name]['root_dn']}" -H ldapi://%2fvar%2frun%2fslapd-#{ds_root_name}.socket -b "cn=tasks,cn=config"))
        # rubocop:enable Layout/LineLength
      end
    end

    context 'when removing a server instance' do
      let(:manifest) do
        'ds389::instance { "scrap": ensure => "absent" }'
      end
      let(:hieradata) do
        { 'ds389::initialize_ds_root' => true }
      end

      it 'clears the hieradata' do
        set_hieradata_on(host, hieradata)
      end

      it 'removes the server instance' do
        expect(directory_exists_on(host, '/etc/dirsrv/slapd-scrap')).to be true

        apply_manifest_on(host, manifest, catch_failures: true)

        expect(directory_exists_on(host, '/etc/dirsrv/slapd-scrap')).to be false
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end
    end

    context 'with an admin service' do
      let(:ds_root_name) { 'admin_test' }
      let(:hieradata) do
        {
          'ds389::initialize_ds_root' => true,
          'ds389::ds_root_name' => ds_root_name,
          'ds389::port' => 390,
          'ds389::enable_admin_service' => true
        }
      end

      it 'enables the admin service' do
        set_hieradata_on(host, hieradata)
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'can login to 389DS' do
        on(host, %(ldapsearch -x -y "#{admin_password_file}" -D "cn=Directory_Manager" -h localhost -p #{hieradata['ds389::port']} -b "cn=tasks,cn=config"))
      end

      it 'can login to 389DS via LDAPI' do
        on(host, %(ldapsearch -x -y "#{admin_password_file}" -D "cn=Directory_Manager" -H ldapi://%2fvar%2frun%2fslapd-#{ds_root_name}.socket -b "cn=tasks,cn=config"))
      end
    end
  end
end
