require 'spec_helper'

describe Spree::User do
  it { is_expected.to have_many(:unified_payments).class_name('UnifiedPayment::Transaction') }

  describe 'create_unified_transaction_user' do
    it 'creates a new user' do
      expect(Spree::User.where(:email => 'new_user@unified.com')).to be_blank
      expect(Spree::User.create_unified_transaction_user('new_user@unified.com')).to eq(Spree::User.where(:email => 'new_user@unified.com').first )
    end
  end
end