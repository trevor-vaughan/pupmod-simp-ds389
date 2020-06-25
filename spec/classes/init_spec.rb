# frozen_string_literal: true

require 'spec_helper'

describe 'ds389' do
  context 'on supported operating systems' do
    on_supported_os.each do |os, _facts|
      context "on #{os}" do
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to create_class('ds389::install') }
        it { is_expected.not_to create_ds389__instance('puppet_default_root') }
      end
    end
  end
end
