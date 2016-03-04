require 'spec_helper'

describe Spree::TransactionNotificationMailer do
  let(:card_transaction) { mock_model(UnifiedPayment::Transaction, :status => 'successful', :xml_response => '') }
  let(:order) { mock_model(Spree::Order) }
  let(:user) { mock_model(Spree::User) }
  let!(:store) { Spree::Store.create!(mail_from_address: 'test@testmail.com', code: '1234', name: 'test', url: 'www.test.com') }

  before do
    @email = "test_user@westaycute.com"
    allow(order).to receive(:line_items).and_return([])
    allow(card_transaction).to receive(:order).and_return(order)
    allow(card_transaction).to receive(:user).and_return(user)
    allow(user).to receive(:email).and_return(@email)
  end
  describe 'fetches info from card_transaction' do
    it { expect(card_transaction).to receive(:order).and_return(order) }
    it do
      expect(card_transaction).to receive(:user).and_return(order)
      card_transaction.user.email
    end
    it { expect(user).to receive(:email).and_return(@email) }
    it { expect(card_transaction).to receive(:status).and_return(card_transaction.status) }
    it { expect(card_transaction).to receive(:xml_response).and_return('') }

    after do
      Spree::TransactionNotificationMailer.send_mail(card_transaction).deliver_now
    end
  end

  context 'when xml response is a message' do
    before do 
      allow(card_transaction).to receive(:xml_response).and_return("<Message><OrderStatus>Approved</OrderStatus></Message>")
    end

    it { expect(Hash).to receive(:from_xml).with(card_transaction.xml_response).and_return({'Message' => { 'OrderStatus' => 'Approved'} } ) }
    after do
      Spree::TransactionNotificationMailer.send_mail(card_transaction).deliver_now
    end
  end

  context 'when xml response is not a message' do
    before do 
      allow(card_transaction).to receive(:xml_response).and_return("<NoMessage></NoMessage>")
    end

    it { expect(Hash).not_to receive(:from_xml) }
    after do
      Spree::TransactionNotificationMailer.send_mail(card_transaction).deliver_now
    end
  end
end
