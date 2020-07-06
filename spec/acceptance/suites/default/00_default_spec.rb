# frozen_string_literal: true

require 'spec_helper_acceptance'

test_name 'Set up 389DS'

describe 'Set up 389DS' do
  let(:manifest) do
    'include ds389'
  end

  hosts.each do |host|
    context "on #{host}" do
      it 'has a proper FQDN' do
        on(host, "hostname #{fact_on(host, 'fqdn')}")
        on(host, 'hostname -f > /etc/hostname')
      end
    end
  end

  hosts_with_role(hosts, 'directory_server').each do |host|
    let(:ds_root_name) { 'puppet_default_root' }
    let(:admin_password) do
      # rubocop:disable RSpec/InstanceVariable
      @admin_password ||= on(host,
                             "cat `puppet config print vardir`/simp/environments/production/simp_autofiles/gen_passwd/389-ds-#{ds_root_name}").stdout.strip

      @admin_password
      # rubocop:enable RSpec/InstanceVariable
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
        { 'ds389::initialize_ds_root' => true }
      end

      it 'works with no errors' do
        set_hieradata_on(host, hieradata)
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'is running ns-slapd' do
        on(host, 'ss -tlpn | grep ns-slapd')
      end

      it 'can login to 389DS' do
        on(host, %(ldapsearch -x -w "#{admin_password}" -D "cn=Directory Manager" -h `hostname -f` -b "cn=tasks,cn=config"))
      end

      it 'fails when logging in with forced encryption' do
        expect { on(host, %(ldapsearch -ZZ -x -w "#{admin_password}" -D "cn=Directory Manager" -h `hostname -f` -b "cn=tasks,cn=config")) }.to raise_error(Beaker::Host::CommandFailure)
      end
    end

    context 'with an admin service' do
      let(:ds_root_name) { 'admin_test' }
      let(:hieradata) do
        {
          'ds389::initialize_ds_root'   => true,
          'ds389::ds_root_name'         => ds_root_name,
          'ds389::port'                 => 390,
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
        on(host, %(ldapsearch -x -w "#{admin_password}" -D "cn=Directory Manager" -h `hostname -f` -p 390 -b "cn=tasks,cn=config"))
      end
    end

    context 'when removing a server instance' do
      let(:manifest) do
        'ds389::instance { "admin_test": ensure => "absent" }'
      end

      it 'removes the server instance' do
        expect(directory_exists_on(host, '/etc/dirsrv/slapd-admin_test')).to be true

        apply_manifest_on(host, manifest, catch_failures: true)

        expect(directory_exists_on(host, '/etc/dirsrv/slapd-admin_test')).to be false
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end
    end
  end
end
