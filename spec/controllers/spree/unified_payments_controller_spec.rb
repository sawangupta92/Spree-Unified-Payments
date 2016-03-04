require 'spec_helper'

describe Spree::UnifiedPaymentsController do

  let(:user) { mock_model(Spree.user_class) }
  let(:order) { mock_model(Spree::Order, :total => '12') }
  let(:variant) { mock_model(Spree::Variant, :name => 'test-variant') }
  let!(:store) { Spree::Store.create!(mail_from_address: 'test@testmail.com', code: '1234', name: 'test', url: 'www.test.com') }

  before(:each) do
    allow(user).to receive(:generate_spree_api_key!).and_return(true)
    allow(user).to receive(:last_incomplete_spree_order).and_return(order)
    allow(controller).to receive(:spree_current_user).and_return(user)
    allow(controller).to receive(:current_order).and_return(order)
    allow(user).to receive(:orders).and_return(order)
    allow(order).to receive(:incomplete).and_return(Spree::Order.where(state: 'incomplete'))
  end

  context 'before going to gateway' do 
    before do
      allow(order).to receive(:user).and_return(user)
      allow(order).to receive(:completed?).and_return(false)
      allow(order).to receive(:insufficient_stock_lines).and_return([])
      allow(order).to receive(:pending_card_transaction).and_return(nil)
      allow(order).to receive(:inactive_variants).and_return([])
      allow(order).to receive(:reason_if_cant_pay_by_card).and_return(nil)
    end

    describe '#ensure_and_load_order' do
      def send_request(params = {})
        get :new, params.merge!({:use_route => 'spree'})
      end

      context 'when current order does not exist' do
        before do 
          allow(controller).to receive(:current_order).and_return(nil)
        end

        it 'does not call for reason_if_cant_pay_by_card on order' do
          expect(order).not_to receive(:reason_if_cant_pay_by_card)
          send_request
        end

        it 'response should redirect to cart' do
          send_request
          expect(response).to redirect_to '/cart'
        end

        it 'sets flash message' do
          send_request
          expect(flash[:error]).to eq('Order not found')
        end
      end

      context 'when current order exists with no errors' do
        before { allow(order).to receive(:reason_if_cant_pay_by_card).and_return(nil) }
        
        it 'calls for reason_if_cant_pay_by_card on order' do
          expect(order).to receive(:reason_if_cant_pay_by_card).and_return(nil)
          send_request
        end

        it 'loads order' do
          send_request
          expect(assigns(:order)).to eq(order)
        end

        it 'sets no error message' do
          expect(flash[:error]).to be_nil
        end
      end

      context 'order exists but no valid' do
        before do 
          allow(order).to receive(:reason_if_cant_pay_by_card).and_return('Order is already completed.')
        end
        
        it 'calls for reason_if_cant_pay_by_card on order' do
          expect(order).to receive(:reason_if_cant_pay_by_card).and_return('Order is already completed.')
          send_request
        end

        it 'sets the flash message' do
          send_request
          expect(flash[:error]).to eq('Order is already completed.')
        end

        it 'gives a js response to redirect to cart' do
          send_request
          expect(response).to redirect_to '/cart'
        end
      end
    end
    
    describe '#index' do
      before do
        @unified_payment = mock_model(UnifiedPayment::Transaction)
        @unified_payments = [@unified_payment]
        allow(@unified_payments).to receive(:order).with('updated_at desc').and_return(@unified_payments)
        allow(@unified_payments).to receive(:page).with('1').and_return(@unified_payments)
        allow(@unified_payments).to receive(:per).with(20).and_return(@unified_payments)
        allow(user).to receive(:unified_payments).and_return(@unified_payments)
      end

      def send_request(params = {})
        get :index, params.merge!({:use_route => 'spree'})
      end

      it { expect(user).to receive(:unified_payments).and_return(@unified_payments) }
      it { expect(@unified_payments).to receive(:order).with('updated_at desc').and_return(@unified_payments) }
      it { expect(@unified_payments).to receive(:page).with('1').and_return(@unified_payments) }
      it { expect(@unified_payments).to receive(:per).with(20).and_return(@unified_payments) }
      after { send_request(:page => '1') }
    end


    describe '#new' do

      def send_request(params = {})
        get :new, params.merge!({:use_route => 'spree'})
      end

      before { allow(controller).to receive(:generate_transaction_id).and_return(12345678910121) }

      describe 'method calls' do
        it { expect(controller).to receive(:generate_transaction_id).and_return(12345678910121) }
        
        after { send_request }
      end
      
      describe 'assigns' do
        before { send_request }

        it { expect(session[:transaction_id]).to eq(12345678910121) }
      end
    end

    describe '#create' do

      def send_request(params = {})
        post :create, params.merge!({:use_route => 'spree'})
      end

      before do
        session[:transaction_id] = '12345678910121'
        @gateway_response = Object.new
        allow(UnifiedPayment::Transaction).to receive(:create_order_at_unified).with(order.total, {:approve_url=>"http://test.host/unified_payments/approved", :cancel_url=>"http://test.host/unified_payments/canceled", :decline_url=>"http://test.host/unified_payments/declined", :description=>"Purchasing items from #{Spree::Store.first.name}"}).and_return(@gateway_response)
        allow(UnifiedPayment::Transaction).to receive(:extract_url_for_unified_payment).with(@gateway_response).and_return("www.#{Spree::Store.first.name}.com")
        allow(controller).to receive(:tasks_on_gateway_create_response).with(@gateway_response, '12345678910121').and_return(true)
      end

      context 'with a pending card transaction' do
        before do
          @pending_card_transaction = mock_model(UnifiedPayment::Transaction, :payment_transaction_id => '98765432110112')
          allow(@pending_card_transaction).to receive(:abort!).and_return(true)
          allow(order).to receive(:pending_card_transaction).and_return(@pending_card_transaction)
        end

        describe 'method calls' do
          it { expect(order).to receive(:pending_card_transaction).and_return(@pending_card_transaction) }
          it { expect(@pending_card_transaction).to receive(:abort!).and_return(true) }
        
          after { send_request }
        end
      end

      context 'with no card transaction' do
        before { allow(order).to receive(:pending_card_transaction).and_return(nil) }

        describe 'method calls' do
          it { expect(order).to receive(:pending_card_transaction).and_return(nil) }
          
          after { send_request }
        end
      end

      context 'when an order is successfully created at gateway' do
        
        describe 'method calls' do
          it { expect(UnifiedPayment::Transaction).to receive(:create_order_at_unified).with(order.total, {:approve_url=>"http://test.host/unified_payments/approved", :cancel_url=>"http://test.host/unified_payments/canceled", :decline_url=>"http://test.host/unified_payments/declined", :description=>"Purchasing items from #{Spree::Store.first.name}"}).and_return(@gateway_response) }
          it { expect(UnifiedPayment::Transaction).to receive(:extract_url_for_unified_payment).with(@gateway_response).and_return("www.#{Spree::Store.first.name}.com") }
          it { expect(controller).to receive(:tasks_on_gateway_create_response).with(@gateway_response, '12345678910121').and_return(true) }
          
          after { send_request }
        end
        
        describe 'assigns' do
          it 'payment_url' do
            send_request
            expect(assigns(:payment_url)).to eq("www.#{Spree::Store.first.name}.com")
          end
        end
      end

      context 'when order not created at gateway' do
        
        before { allow(UnifiedPayment::Transaction).to receive(:create_order_at_unified).with(order.total, {:approve_url=>"http://test.host/unified_payments/approved", :cancel_url=>"http://test.host/unified_payments/canceled", :decline_url=>"http://test.host/unified_payments/declined", :description=>"Purchasing items from #{Spree::Store.first.name}"}).and_return(false) }
        
        describe 'method calls' do
          it { expect(UnifiedPayment::Transaction).to receive(:create_order_at_unified).with(order.total, {:approve_url=>"http://test.host/unified_payments/approved", :cancel_url=>"http://test.host/unified_payments/canceled", :decline_url=>"http://test.host/unified_payments/declined", :description=>"Purchasing items from #{Spree::Store.first.name}"}).and_return(false) }
          it { expect(UnifiedPayment::Transaction).not_to receive(:extract_url_for_unified_payment) }
          it { expect(controller).not_to receive(:tasks_on_gateway_create_response) }
          
          after { send_request }
        end
      end

      context 'before filter' do
        describe '#ensure_session_transaction_id' do
          context 'when no session transaction id' do
            before do
              session[:transaction_id] = nil
              send_request
            end

            it { expect(flash[:error]).to eq('No transaction id found, please try again') }
            it { expect(response.body).to eq("top.location.href = 'http://test.host/checkout/payment'") }
          end

          context 'when session transaction_id present' do
            before { send_request }

            it { expect(flash[:error]).to be_nil }
            it { expect(response.body).to eq("$('#confirm_payment').hide();top.location.href = 'www.#{Spree::Store.first.name}.com'") }
          end
        end
      end
    end

    describe '#tasks_on_gateway_create_response' do
      def send_request(params = {})
        post :create, params.merge!({:use_route => 'spree'})
      end

      before do
        session[:transaction_id] = '12345678910121'
        allow(order).to receive(:reserve_stock).and_return(true)
        allow(order).to receive(:next).and_return(true)
        @gateway_response = {'Status' => 'status', 'Order' => { 'SessionID' => '12312', 'OrderID' => '123121', 'URL' => 'MyResponse'}}
        @transaction = UnifiedPayment::Transaction.new
        allow(UnifiedPayment::Transaction).to receive(:create_order_at_unified).with(order.total, {:approve_url=>"http://test.host/unified_payments/approved", :cancel_url=>"http://test.host/unified_payments/canceled", :decline_url=>"http://test.host/unified_payments/declined", :description=>"Purchasing items from #{Spree::Store.first.name}"}).and_return(@gateway_response)
        allow(UnifiedPayment::Transaction).to receive(:extract_url_for_unified_payment).with(@gateway_response).and_return("www.#{Spree::Store.first.name}.com")
        allow(UnifiedPayment::Transaction).to receive(:where).with(:gateway_session_id => '12312', :gateway_order_id => '123121', :url => 'MyResponse').and_return([@transaction])
        allow(@transaction).to receive(:save!).and_return(true)
      end

      describe 'method calls' do
        context 'when order state is payment' do
          before { allow(order).to receive(:state).and_return('payment') }
          it { expect(order).to receive(:reserve_stock).and_return(true) }
          it { expect(order).to receive(:next).and_return(true) }

          after { send_request }
        end

        context 'when order state is not payment' do
          it { expect(order).to receive(:reserve_stock).and_return(true) }
          it { expect(order).not_to receive(:next) }
          it { expect(UnifiedPayment::Transaction).to receive(:where).with(:gateway_session_id => '12312', :gateway_order_id => '123121', :url => 'MyResponse').and_return([@transaction]) }
          it { expect(@transaction).to receive(:assign_attributes).with({:user_id => order.user.try(:id), :payment_transaction_id => '12345678910121', :order_id => order.id, :gateway_order_status => 'CREATED', :amount => order.total, :currency => Spree::Config[:currency], :response_status => 'status', :status => 'pending'}).and_return(true) }
          it { expect(@transaction).to receive(:save!).and_return(true) }
          after { send_request }
        end
      end

      describe 'assigns' do
        before { send_request }

        it { expect(session[:transaction_id]).to be_nil }
      end
    end
  end

  context 'on return from gateway' do
    before do
      @card_transaction = mock_model(UnifiedPayment::Transaction)
      allow(@card_transaction).to receive(:approved_at_gateway?).and_return(false)
      allow(@card_transaction).to receive(:order).and_return(order)
      allow(UnifiedPayment::Transaction).to receive_message_chain(:where, :first).and_return(@card_transaction)
    end

    context 'as declined' do
      describe '#declined' do
        
        def send_request(params = {})
          post :declined, params.merge!({:use_route => 'spree'})
        end
        
        before do
          allow(@card_transaction).to receive(:assign_attributes).with(:status => 'unsuccessful', :xml_response => '<Message><Hash>Mymessage</Hash><ResponseDescription>Reason</ResponseDescription></Message>').and_return(true)
          allow(@card_transaction).to receive(:save).with(:validate => false).and_return(true)
        end

        describe 'method calls' do
          
          it { expect(@card_transaction).to receive(:order).and_return(order) }
          it { expect(@card_transaction).to receive(:assign_attributes).with(:status => 'unsuccessful', :xml_response => '<Message><Hash>Mymessage</Hash><ResponseDescription>Reason</ResponseDescription></Message>').and_return(true) }
          it { expect(@card_transaction).to receive(:save).with(:validate => false).and_return(true) } 
          
          after { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash><ResponseDescription>Reason</ResponseDescription></Message>'}) }
        end
      end
    end

    context 'as canceled' do
      def send_request(params = {})
        post :canceled, params.merge!({:use_route => 'spree'})
      end

      before do
        allow(@card_transaction).to receive(:assign_attributes).with(:status => 'unsuccessful', :xml_response => '<Message><Hash>Mymessage</Hash></Message>').and_return(true)
        allow(@card_transaction).to receive(:save).with(:validate => false).and_return(true)
      end

      context 'before filter' do
        describe '#load_on_redirect' do        
          
          context 'there is a card transaction for the response' do
            before { allow(UnifiedPayment::Transaction).to receive_message_chain(:where, :first).and_return(@card_transaction) }
            
            describe 'method calls' do
              it { expect(@card_transaction).to receive(:order).and_return(order) }
              it { expect(controller).not_to receive(:verify_authenticity_token) }

              after { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash></Message>'}) }
            end
            
            describe 'assigns' do
              it 'card_transaction' do
                send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash></Message>'})
                expect(assigns(:card_transaction)).to eq(@card_transaction)
              end
            end
          end

          context 'there is no card transaction for the response' do
            before do
              allow(UnifiedPayment::Transaction).to receive_message_chain(:where, :first).and_return(nil)
              send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash></Message>'})
            end

            describe 'method calls' do
              it { expect(flash[:error]).to eq('No transaction. Please contact our support team.') }
              it { expect(response).to redirect_to('/') }
            
              after { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash></Message>'}) }
            end
            
            describe 'assigns' do
              it 'card_transaction' do
                send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash></Message>'})
                expect(assigns(:card_transaction)).to be_nil
              end
            end
          end
        end
      end

      describe '#canceled' do
        
        describe 'method calls' do
          it { expect(@card_transaction).to receive(:assign_attributes).with(:status => 'unsuccessful', :xml_response => '<Message><Hash>Mymessage</Hash></Message>').and_return(true) }
          it { expect(@card_transaction).to receive(:save).with(:validate => false).and_return(true) }
          it { expect(controller).not_to receive(:verify_authenticity_token) }

          after { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash></Message>'}) }
        end
      end
    end

    describe '#approved' do      
      
      def send_request(params = {})
        post :approved, params.merge!({:use_route => 'spree'})
      end

      before do
        allow(@card_transaction).to receive(:expired_at?).and_return(false)
        allow(@card_transaction).to receive(:xml_response=).with('<Message><Hash>Mymessage</Hash><PurchaseAmountScr>200</PurchaseAmountScr></Message>').and_return(true)
        allow(@card_transaction).to receive(:status=).with("successful").and_return(true)
        allow(@card_transaction).to receive(:status=).with("unsuccessful").and_return(true)
        allow(@card_transaction).to receive(:save).with(:validate => false).and_return(true)
        allow(order).to receive(:paid?).and_return(true)
      end

      describe 'method calls' do
        it { expect(@card_transaction).to receive(:order).and_return(order) }
        it { expect(controller).not_to receive(:verify_authenticity_token) }
      
        after { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash><PurchaseAmountScr>200</PurchaseAmountScr></Message>'}) }
      end

      context 'approved at gateway' do
        before { allow(@card_transaction).to receive(:approved_at_gateway?).and_return(true) }

        context 'payment made at gateway is not as in card transaction' do
          before { allow(@card_transaction).to receive(:amount).and_return(100) }
          it { expect(controller).to receive(:add_error).with("Payment made was not same as requested to gateway. Please contact administrator for queries.").and_return(true) }
          it { expect(@card_transaction).to receive(:status=).with('unsuccessful').and_return(true) }
        
          after { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash><PurchaseAmountScr>200</PurchaseAmountScr></Message>'}) }
        end

        context 'payment made at gateway is same as in card transaction' do
          before { allow(@card_transaction).to receive(:amount).and_return(200) }
          context 'transaction has expired' do
            before { allow(@card_transaction).to receive(:expired_at?).and_return(true) }

            describe 'assigns' do
              before { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash><PurchaseAmountScr>200</PurchaseAmountScr></Message>'}) }

              it { expect(assigns(:transaction_expired)).to be_truthy }
              it { expect(assigns(:payment_made)).to eq(200) }
            end

            describe 'method_calls' do
              it { expect(controller).to receive(:add_error).with('Payment was successful but transaction has expired. The payment made has been walleted in your account. Please contact administrator to help you further.').and_return(true) }
              it { expect(@card_transaction).to receive(:status=).with('successful').and_return(true) }

              after { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash><PurchaseAmountScr>200</PurchaseAmountScr></Message>'}) }
            end
          end

          context 'transaction has not expired' do

            describe 'assigns' do
              before { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash><PurchaseAmountScr>200</PurchaseAmountScr></Message>'}) }
      
              it { expect(assigns(:transaction_expired)).to be_falsey }
            end

            context 'order has not been paid or completed' do
              before do
                allow(order).to receive(:completed?).and_return(false)
                allow(order).to receive(:paid?).and_return(false)
              end
              
              it { expect(@card_transaction).to receive(:status=).with('successful').and_return(true) }
              
              after { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash><PurchaseAmountScr>200</PurchaseAmountScr></Message>'}) }
            end

            context 'order already completed' do
              before do
                allow(order).to receive(:completed?).and_return(true)
                allow(order).to receive(:paid?).and_return(false)
              end

              it { expect(@card_transaction).to receive(:status=).with('successful').and_return(true) }
              it { expect(controller).to receive(:add_error).with('Order Already Paid Or Completed').and_return(true) }
            
              after { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash><PurchaseAmountScr>200</PurchaseAmountScr></Message>'}) }
            end

            context 'order already paid' do
              it { expect(controller).to receive(:add_error).with('Order Already Paid Or Completed').and_return(true) }
              it { expect(@card_transaction).to receive(:status=).with('successful').and_return(true) }
 
              after { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash><PurchaseAmountScr>200</PurchaseAmountScr></Message>'}) }
            end

            context 'order total is not same as card total' do
              before do
                allow(order).to receive(:completed?).and_return(false)
                allow(order).to receive(:paid?).and_return(false)
                allow(order).to receive(:total).and_return(100)
                allow(@card_transaction).to receive(:amount).and_return(200)
              end
              it { expect(controller).to receive(:add_error).with("Payment made is different from order total. Payment made has been walleted to your account.").and_return(true) }
              it { expect(@card_transaction).to receive(:status=).with('successful').and_return(true) }
              it { expect(@card_transaction).to receive(:save).with(:validate => false).and_return(true) }
              
              after { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash><PurchaseAmountScr>200</PurchaseAmountScr></Message>'}) }
            end
          end
        end
      end

      context 'not approved at gateway' do
        before do
          allow(@card_transaction).to receive(:approved_at_gateway?).and_return(false)
        end

        describe 'method calls' do
          it { expect(controller).to receive(:add_error).with('Not Approved At Gateway').and_return(true) }
          it { expect(@card_transaction).not_to receive(:amount) }
          it { expect(@card_transaction).not_to receive(:status=) }
          it { expect(order).not_to receive(:paid?) }
          it { expect(order).not_to receive(:completed?) }
          
          after { send_request({:xmlmsg => '<Message><Hash>Mymessage</Hash><PurchaseAmountScr>200</PurchaseAmountScr></Message>'}) }
        end
      end
    end
  end
end
