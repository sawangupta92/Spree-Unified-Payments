require 'spec_helper'

describe Spree::CheckoutController do
  let(:user) { mock_model(Spree.user_class) }
  let(:role) { mock_model(Spree::Role) }
  let(:roles) { [role] }
  let(:order) { Spree::Order.new }
  let(:payment) { mock_model(Spree::Payment) }
  let(:variant) { mock_model(Spree::Variant, :name => 'test-variant') }
  let!(:store) { Spree::Store.create!(mail_from_address: 'test@testmail.com', code: '1234', name: 'test', url: 'www.test.com') }

  before(:each) do
    allow(controller).to receive(:spree_current_user).and_return(user)
    allow(user).to receive(:generate_spree_api_key!).and_return(true)
    allow(controller).to receive(:authenticate_spree_user!).and_return(true)
    allow(user).to receive(:roles).and_return(roles)
    allow(controller).to receive(:authorize!).and_return(true)
    allow(roles).to receive(:includes).and_return(roles)
    allow(role).to receive(:ability).and_return(true)
    allow(user).to receive(:last_incomplete_spree_order).and_return(nil)
    allow(controller).to receive(:load_order).and_return(true)
    allow(controller).to receive(:load_order_with_lock).and_return(true)
    allow(controller).to receive(:ensure_order_not_completed).and_return(true)
    allow(controller).to receive(:ensure_checkout_allowed).and_return(true)
    allow(controller).to receive(:ensure_sufficient_stock_lines).and_return(true)
    allow(controller).to receive(:ensure_valid_state).and_return(true)
    allow(controller).to receive(:ensure_active_variants).and_return(true)

    allow(controller).to receive(:associate_user).and_return(true)
    allow(controller).to receive(:check_authorization).and_return(true)
    allow(controller).to receive(:object_params).and_return('object_params')
    allow(controller).to receive(:after_update_attributes).and_return(false)
    controller.instance_variable_set(:@order, order)
    allow(order).to receive(:has_checkout_step?).with('payment').and_return(true)
    allow(order).to receive(:payment?).and_return(false)
    allow(order).to receive(:update_attributes).and_return(false)
    allow(order).to receive(:update_attributes).with({"payments_attributes"=>[{"payment_method_id"=>"1"}]}).and_return(false)
    @payments = [payment]
    allow(@payments).to receive(:reload).and_return(true)
    allow(@payments).to receive(:completed).and_return([])
    allow(@payments).to receive(:valid).and_return([])
    @payment_method = mock_model(Spree::PaymentMethod, :type => 'Spree::PaymentMethod::UnifiedPaymentMethod')
    allow(payment).to receive(:payment_method).and_return(@payment_method)
    allow(order).to receive(:payments).and_return(@payments)
    allow(order).to receive(:next).and_return(true)
    allow(order).to receive(:completed?).and_return(false)
    allow(order).to receive(:state).and_return('payment')
    allow(user).to receive(:orders).and_return(order)
  end

  describe '#redirect_for_card_payment' do
    def send_request(params = {})
      put :update, params.merge!({:use_route => 'spree'})
    end

    context 'if payment state' do
      before do
        allow(@payment_method).to receive(:is_a?).with(Spree::PaymentMethod::UnifiedPaymentMethod).and_return(true)
      end

      context 'when params[:order].present?' do
        before { allow(Spree::PaymentMethod).to receive(:where).with(:id => '1').and_return([@payment_method]) }

        describe 'method calls' do
          it { expect(order).to receive(:update_attributes).with({"payments_attributes"=>[{"payment_method_id"=>"1", "request_env"=>{}}]}).and_return(false) }
          it { expect(@payment_method).to receive(:is_a?).with(Spree::PaymentMethod::UnifiedPaymentMethod).and_return(true) }
          it { expect(Spree::PaymentMethod).to receive(:where).with(:id => '1').and_return([@payment_method]) }
          it { expect(order).not_to receive(:update) }
          after { send_request({"order"=>{"payments_attributes"=>[{"payment_method_id"=>"1"}]}, "state"=>"payment"}) }
        end

        it 'should redirect to unified_payment#new' do
          send_request({"order"=>{"payments_attributes"=>[{"payment_method_id"=>"1"}]}, "state"=>"payment"})
          expect(response).to redirect_to(new_unified_transaction_path)
        end
      end

      context 'when !params[:order].present?' do
        it 'should not redirect to unified_payment#new' do
          send_request({"state" => "payment"})
          expect(response).not_to redirect_to(new_unified_transaction_path)
        end

        describe 'method calls' do
          it { expect(order).to receive(:update_attributes).with({}).exactly(1).times.and_return(true) }
          it { expect(Spree::PaymentMethod).to receive(:where).with(:id => nil).and_return([]) }
          after do
            send_request({"state" => "payment"})
          end
        end
      end

      context 'when !params[:order][:payments_attributes].present?' do
        it 'should not redirect to pay_by_card#new' do
          send_request({"state" => "payment"})
          expect(response).not_to redirect_to(new_unified_transaction_path)
        end

        describe 'method calls' do
          it { expect(order).not_to receive(:update) }
          it { expect(order).to receive(:update_attributes).with({"payments_attributes"=>[{"request_env" => request.env}]}).exactly(1).times.and_return(true) }
          it { expect(Spree::PaymentMethod).to receive(:where).with(:id => nil).and_return([]) }
          after do
            send_request({"order"=>{"payments_attributes"=>[{}]}, "state"=>"payment"})
          end
        end
      end
    end

    context 'if not payment state' do
      before(:each) do
        allow(order).to receive(:has_checkout_step?).with('delivery').and_return(true)
      end
      it { expect(Spree::PaymentMethod).not_to receive(:where).with(:id => '1') }
      it { expect(controller).not_to receive(:redirect_for_card_payment) }

      after do
        send_request({"order"=>{"payments_attributes"=>[{"payment_method_id"=>"1"}]}, "state"=>"delivery"})
      end
    end
  end
end
