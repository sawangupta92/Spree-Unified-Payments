require 'spec_helper'

describe Spree::Admin::UnifiedPaymentsController do
  let(:user) { mock_model(Spree::User) }
  let(:role) { mock_model(Spree::Role) }
  let(:card_transaction) { UnifiedPayment::Transaction.new( :gateway_order_id => '123213', :gateway_session_id => '1212', :payment_transaction_id => '123456', :xml_response => '<Message>123</Message>') }
  let(:order) { mock_model(Spree::Order) }
  let(:roles) { [role] }

  before do
    allow(controller).to receive(:spree_current_user).and_return(user)
    allow(controller).to receive(:authorize_admin).and_return(true)
    allow(controller).to receive(:authorize!).and_return(true)
    allow(user).to receive(:generate_spree_api_key!).and_return(true)
    allow(user).to receive(:roles).and_return(roles)
    allow(roles).to receive(:includes).and_return(roles)
    allow(role).to receive(:ability).and_return(true)
    allow(card_transaction).to receive(:order).and_return(order)
  end

  describe '#index' do
    def send_request(params = {})
      get :index, params.merge!(:use_route => 'spree', :page => 0)
    end

    before do
      allow(UnifiedPayment::Transaction).to receive(:order).with('updated_at desc').and_return(UnifiedPayment::Transaction)
      allow(UnifiedPayment::Transaction).to receive(:ransack).with({}).and_return(UnifiedPayment::Transaction)
      allow(UnifiedPayment::Transaction).to receive_message_chain(:result, :page, :per).with(0).with(20).and_return([card_transaction])
    end
    
    describe 'method calls' do
      it { expect(UnifiedPayment::Transaction).to receive(:order).with('updated_at desc').and_return(UnifiedPayment::Transaction) }
      it { expect(UnifiedPayment::Transaction).to receive(:ransack).with({}).and_return(UnifiedPayment::Transaction) }
      it { expect(UnifiedPayment::Transaction).to receive(:result) }
      it { expect(UnifiedPayment::Transaction.result.page(0).per(20)).to eq([card_transaction]) }
      
      after do
        send_request
      end
    end

    describe 'assigns' do
      it 'card_transactions' do
        send_request
        expect(assigns(:card_transactions)).to eq([card_transaction])
      end
    end
  end

  describe '#receipt' do
    def send_request(params = {})
      get :receipt, params.merge!(:use_route => 'spree')
    end

    context 'Transaction present' do
      before do
        allow(UnifiedPayment::Transaction).to receive(:where).with(:payment_transaction_id => '123456').and_return([card_transaction])
      end
      
      describe 'method calls' do
        it { expect(UnifiedPayment::Transaction).to receive(:where).with(:payment_transaction_id => '123456').and_return([card_transaction]) }
        it { expect(card_transaction).to receive(:order).and_return(order)}

        after do
          send_request(:transaction_id => '123456')
        end
      end

      it 'should render no layout' do
        send_request(:transaction_id => '123456')  
        expect(response).to render_template(:layout => false)
      end

      describe 'assigns' do
        before do
          send_request(:transaction_id => '123456')
        end
        
        it { expect(assigns(:message)).to eq('123') }
      end
    end

    context 'No transaction present' do
      before do
        allow(UnifiedPayment::Transaction).to receive(:where).with(:payment_transaction_id => '123456').and_return([])
      end
      
      describe 'method calls' do
        it { expect(UnifiedPayment::Transaction).to receive(:where).with(:payment_transaction_id => '123456').and_return([]) }
        it { expect(card_transaction).not_to receive(:order) }

        after do
          send_request(:transaction_id => '123456')
        end
      end

      it 'renders js' do
        send_request(:transaction_id => '123456')
        expect(response.body).to eq("alert('Could not find transaction')")
      end
    end
  end

  describe '#query_gateway' do
    def send_request(params = {})
      xhr :get, :query_gateway, params.merge!(:use_route => 'spree')
    end

    before do
      allow(card_transaction).to receive(:update_transaction_on_query).with("MyStatus").and_return(true)
      allow(UnifiedPayment::Transaction).to receive(:where).with(:payment_transaction_id => '123456').and_return([card_transaction])
      allow(UnifiedPayment::Client).to receive(:get_order_status).with(card_transaction.gateway_order_id, card_transaction.gateway_session_id).and_return({"orderStatus" => 'MyStatus'})
    end

    describe 'method calls' do
      it { expect(UnifiedPayment::Client).to receive(:get_order_status).with(card_transaction.gateway_order_id, card_transaction.gateway_session_id).and_return({"orderStatus" => 'MyStatus'}) }
      it { expect(card_transaction).to receive(:update_transaction_on_query).with('MyStatus').and_return(true) }
      after do
        send_request(:transaction_id => '123456')
      end
    end

    describe 'before filters' do
      describe 'load_transactions' do
        it { expect(UnifiedPayment::Transaction).to receive(:where).with(:payment_transaction_id => '123456').and_return([card_transaction]) }
      
        after do
          send_request(:transaction_id => '123456')
        end
      end
    end

    context 'approved status fetched' do
      subject { described_class.token }
      before do
        allow(UnifiedPayment::Client).to receive(:get_order_status).with(card_transaction.gateway_order_id, card_transaction.gateway_session_id).and_return({"orderStatus" => 'APPROVED'})
        allow(card_transaction).to receive(:update_transaction_on_query).with('APPROVED').and_return(true)
      end

      it { expect(card_transaction).to receive(:update_transaction_on_query).with('APPROVED').and_return(true) }

      after do
        send_request(:transaction_id => '123456')
      end
    end

    context 'approved status not fetched' do
      it { expect(card_transaction).to receive(:update_transaction_on_query).with('MyStatus') }
      
      after do
        send_request(:transaction_id => '123456')
      end
    end
  end
end
