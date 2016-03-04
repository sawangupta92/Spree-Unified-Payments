require 'spec_helper'

describe Spree::Order do
  let(:user) { mock_model(Spree::User, email: 'user@testmail.com') }
  let!(:store) { Spree::Store.create!(mail_from_address: 'test@testmail.com', code: '1234', name: 'test', url: 'www.test.com') }
  before(:each) do
    @order = Spree::Order.create!(user: user)
  end
  describe 'Associations' do
    it { is_expected.to have_many(:unified_transactions) }
  end

  describe "#pending_card_transaction" do
    before do
      allow_any_instance_of(UnifiedPayment::Transaction).to receive(:wallet_transaction).and_return(true)
      allow_any_instance_of(UnifiedPayment::Transaction).to receive(:enqueue_expiration_task).and_return(true)
      allow_any_instance_of(UnifiedPayment::Transaction).to receive(:assign_attributes_using_xml).and_return(true)
      allow_any_instance_of(UnifiedPayment::Transaction).to receive(:complete_order).and_return(true)
      allow_any_instance_of(UnifiedPayment::Transaction).to receive(:notify_user_on_transaction_status).and_return(true)
      @successful_card_transaction = @order.unified_transactions.create!(:status => 'successful', :payment_transaction_id => '1234', :amount => 100)
      @pending_card_transaction = @order.unified_transactions.create!(:status => 'pending', :payment_transaction_id => '1234', :amount => 100)
    end

    it { expect(@order.pending_card_transaction).to eq(@pending_card_transaction) }
  end
  
  describe '#reserve_stock' do
    before do
      @pending_inventory_unit = mock_model(Spree::InventoryUnit, :pending => true)
      @order_shipment_with_pending_units = mock_model(Spree::Shipment)
      allow(@order_shipment_with_pending_units).to receive(:finalize!).and_return(true)
      allow(@order_shipment_with_pending_units).to receive(:update!).with(@order).and_return(true)
      allow(@order_shipment_with_pending_units).to receive(:inventory_units).and_return([@pending_inventory_unit])

      @unpending_inventory_unit = mock_model(Spree::InventoryUnit, :pending => false)
      @order_shipment_without_pending_units = mock_model(Spree::Shipment)
      allow(@order_shipment_without_pending_units).to receive(:inventory_units).and_return([@unpending_inventory_unit])
      allow(@order).to receive(:shipments).and_return([@order_shipment_with_pending_units, @order_shipment_without_pending_units])
    end

    it { expect(@order).to receive(:shipments).and_return([@order_shipment_with_pending_units, @order_shipment_without_pending_units]) }
    it { expect(@order_shipment_with_pending_units).to receive(:update!).with(@order).and_return(true) }
    it { expect(@order_shipment_with_pending_units).to receive(:finalize!).and_return(true) }
    it { expect(@order_shipment_without_pending_units).not_to receive(:update!).with(@order) }
    it { expect(@order_shipment_without_pending_units).not_to receive(:finalize!) }

    after do
      @order.reserve_stock
    end
  end

  describe '#create_proposed_shipments' do
    before do
      @order_shipment = mock_model(Spree::Shipment)
      inventory_unit = mock_model(Spree::InventoryUnit, :pending => false)
      allow(@order_shipment).to receive(:inventory_units).and_return([inventory_unit])
      allow(@order_shipment).to receive(:cancel).and_return(true)

      @pending_order_shipment = mock_model(Spree::Shipment)
      pending_inventory_unit = mock_model(Spree::InventoryUnit, :pending => true)
      allow(@pending_order_shipment).to receive(:inventory_units).and_return([pending_inventory_unit])

      @shipments = [@order_shipment, @pending_order_shipment]
      allow(@shipments).to receive(:destroy_all).and_return(true)
      allow(@order).to receive(:shipments).and_return(@shipments)
    end

    it { expect(@order_shipment).to receive(:cancel).and_return(true) }
    it { expect(@pending_order_shipment).not_to receive(:cancel) }
    it { expect(@shipments).to receive(:destroy_all).and_return(true) }

    after do
      @order.create_proposed_shipments
    end
  end

  
  describe '#release_inventory' do
    before do
      @pending_inventory_unit = mock_model(Spree::InventoryUnit, :pending => true)
      @order_shipment_with_pending_units = mock_model(Spree::Shipment)
      allow(@order_shipment_with_pending_units).to receive(:finalize!).and_return(true)
      allow(@order_shipment_with_pending_units).to receive(:update!).with(@order).and_return(true)
      allow(@order_shipment_with_pending_units).to receive(:inventory_units).and_return([@pending_inventory_unit])

      @unpending_inventory_unit = mock_model(Spree::InventoryUnit, :pending => false)
      @order_shipment_without_pending_units = mock_model(Spree::Shipment)
      allow(@order_shipment_without_pending_units).to receive(:inventory_units).and_return([@unpending_inventory_unit])
      allow(@order_shipment_without_pending_units).to receive(:cancel).and_return(true)
      allow(@order).to receive(:shipments).and_return([@order_shipment_with_pending_units, @order_shipment_without_pending_units])
    end

    it { expect(@order_shipment_without_pending_units).to receive(:cancel).and_return(true) }
    it { expect(@order_shipment_with_pending_units).not_to receive(:cancel) }

    after do
      @order.release_inventory
    end
  end

  describe '#reason_if_cant_pay_by_card' do
    before do
      @order.total = 100
      # @order.stub(:completed?).and_return(false)
    end

    context 'total is 0' do
      before { @order.total = 0 }
      it { expect(@order.reason_if_cant_pay_by_card).to eq('Order Total is invalid') }
    end

    context 'order is completed' do
      before { allow(@order).to receive(:completed?).and_return(true) }
      it { expect(@order.reason_if_cant_pay_by_card).to eq('Order already completed') }
    end

    context 'order has insufficient stock lines' do
      before { allow(@order).to receive(:insufficient_stock_lines).and_return([0]) }
      it { expect(@order.reason_if_cant_pay_by_card).to eq('An item in your cart has become unavailable.') }
    end
  end

  describe 'finalize!' do
    before do
      allow(@order).to receive(:user_id).and_return(user.id)
      @adjustment = mock_model(Spree::Adjustment)
      allow(@order).to receive(:adjustments).and_return([@adjustment])
      allow(@adjustment).to receive(:update_column).with("state", "closed").and_return(true)
      allow(@order).to receive(:save).and_return(true)
      @order_updater = Spree::OrderUpdater.new(@order)
      allow(@order).to receive(:updater).and_return(@order_updater)
      allow(@order_updater).to receive(:update_shipment_state).and_return(true)
      allow(@order_updater).to receive(:update_payment_state).and_return(true)
      allow(@order_updater).to receive(:run_hooks).and_return(true)
      @state_changes = []
      allow(@state_changes).to receive(:create).with({:previous_state=>'confirm', :next_state=>"complete", :name=>"order", :user_id=>user.id}).and_return(true)

      allow(@order).to receive(:state_changes).and_return(@state_changes)
      allow(@order).to receive(:previous_states).and_return([:delivery, :payment, :confirm])
      allow(@order).to receive(:reserve_stock).and_return(true)
      allow(@adjustment).to receive(:close).and_return(true)
    end

    it 'updates completed at' do
      expect(@order.completed_at).to be_nil
      @order.finalize!
      expect(@order.reload.completed_at).not_to be_nil
      allow(@order).to receive(:deliver_order_confirmation_email).and_return(true)
    end

    it 'udpates adjustments' do
      @order.finalize!
    end

    it 'saves self' do
      expect(@order).to receive(:save!).and_return(true)
      @order.finalize!
    end

    it 'updates shipment states' do
      expect(@order_updater).to receive(:update_shipment_state).and_return(true)
      @order.finalize!
    end

    it 'updates payment states' do
      expect(@order_updater).to receive(:update_payment_state).and_return(true)
      @order.finalize!
    end

    it 'run hooks through updater' do
      expect(@order_updater).to receive(:run_hooks).and_return(true)
      @order.finalize!
    end

    it 'sends email' do
      expect(@order).to receive(:deliver_order_confirmation_email).and_return(true)
      @order.finalize!
    end

    it 'stores state changes' do
      expect(@state_changes).to receive(:create).with({:previous_state=>'confirm', :next_state=>"complete", :name=>"order", :user_id=>user.id}).and_return(true)
      @order.finalize!
    end

    context 'when orders last state was confirm' do
      before do
        allow(@order).to receive(:previous_states).and_return([:delivery, :payment, :confirm])
      end

      it 'does reserve stock' do
        expect(@order).to receive(:reserve_stock)
        @order.finalize!
      end
    end

    context 'when orders last state was not confirm' do
      before do
        allow(@order).to receive(:previous_states).and_return([:delivery, :payment])
        allow(@state_changes).to receive(:create).with({:previous_state=>"payment", :next_state=>"complete", :name=>"order", :user_id=>user.id}).and_return(true)
      end

      it 'reserves stock' do
        expect(@order).to receive(:reserve_stock)
        @order.finalize!
      end
    end
  end
end
