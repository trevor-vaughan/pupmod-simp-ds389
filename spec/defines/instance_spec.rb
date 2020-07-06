# frozen_string_literal: true

require 'spec_helper'

describe 'ds389::instance', :type => :define do
  context 'when on supported operating systems' do
    on_supported_os.each do |os, os_facts|
      context "with #{os}" do
        let(:facts) do
          os_facts
        end

        let(:title) do
          'test'
        end

        context 'when validating options' do
          context 'with an invalid title' do
            let(:title) do
              'bad name'
            end

            it { is_expected.to compile.and_raise_error(%r{must be a valid systemd service name}) }
          end

          context 'with default options' do
            it { is_expected.to compile.and_raise_error(%r{must specify a base_dn}) }
          end

          context 'with base_dn only specified' do
            let(:params) {{
              'base_dn' => 'ou=root,dn=my,dn=domain'
            }}

            it { is_expected.to compile.and_raise_error(%r{must specify a root_dn}) }
          end
        end

        context 'with valid options' do
          let(:params) {{
            'base_dn' => 'ou=root,dn=my,dn=domain',
            'root_dn' => 'cn=Directory Manager'
          }}

          it { is_expected.to compile.with_all_deps }

          context 'with conflicting resource port' do
            let(:pre_condition){
              <<~MANIFEST
              ds389::instance { 'pre_test':
                base_dn => 'ou=root,dn=my,dn=domain',
                root_dn => 'cn=Directory Manager'
              }
              MANIFEST
            }

            it { is_expected.to compile.with_all_deps }
          end
        end
      end
    end
  end
end
