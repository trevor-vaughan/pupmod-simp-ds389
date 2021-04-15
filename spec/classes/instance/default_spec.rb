# frozen_string_literal: true

require 'spec_helper'

describe 'ds389::instance::default' do
  context 'when on supported operating systems' do
    let(:pre_condition) do
      <<~PRE_CONDITION
      function assert_private(){}
      PRE_CONDITION
    end

    on_supported_os.each do |os, os_facts|
      let(:facts) do
        os_facts
      end

      context "with #{os}" do
        it { is_expected.to compile.with_all_deps }

        it do
          expect(subject).to create_ds389__instance('puppet_default')
            .with_listen_address('0.0.0.0')
            .with_enable_tls(false)
            .with_tls_params({})
            .with_base_dn(%r{^dc=})
            .with_root_dn('cn=Directory_Manager')
            .with_bootstrap_ldif_content(%r{gidNumber: 100})
            .with_bootstrap_ldif_content(%r{gidNumber: 700})
            .without_ds_setup_ini_content
        end

        context 'when setting ds_setup_ini_content' do
          let(:params) do
            {
              :instance_params => {
                'ds_setup_ini_content' => 'foo'
              }
            }
          end

          it { is_expected.to compile.with_all_deps }

          it do
            expect(subject).to create_ds389__instance('puppet_default')
              .with_ds_setup_ini_content('foo')
              .without_bootstrap_ldif_content
          end
        end

        context 'when specifying bootstrap_ldif_content' do
          let(:params) do
            {
              :instance_params => {
                'bootstrap_ldif_content' => 'bar'
              }
            }
          end

          it { is_expected.to compile.with_all_deps }

          it do
            expect(subject).to create_ds389__instance('puppet_default')
              .with_bootstrap_ldif_content('bar')
              .without_ds_setup_ini_content
          end
        end

        context 'when enabling TLS' do
          let(:params) do
            {
              :enable_tls => true
            }
          end

          it { is_expected.to compile.with_all_deps }

          it do
            expect(subject).to create_ds389__instance('puppet_default')
              .with_enable_tls(true)

            expect(subject).to create_ds389__instance__tls('puppet_default')
              .with_ensure(true)
          end

          context 'when passing bad parameters' do
            let(:params) do
              {
                :enable_tls => true,
                :tls_params => {
                  :bob => 'alice'
                }
              }
            end

            it do
              expect { expect(subject).to compile.with_all_deps }.to raise_error(%r{no parameter.+bob})
            end
          end

          context 'when configuring TLS settings' do
            let(:params) do
              {
                :enable_tls => true,
                :tls_params => {
                  :cert => '/usr/share/key',
                  :token => '12345678910111213'
                }
              }
            end

            it { is_expected.to compile.with_all_deps }

            it do
              expect(subject).to create_ds389__instance('puppet_default')
                .with_enable_tls(true)

              expect(subject).to create_ds389__instance__tls('puppet_default')
                .with_ensure(true)
                .with_cert(params[:tls_params][:cert])
                .with_token(params[:tls_params][:token])
            end
          end
        end
      end
    end
  end
end
