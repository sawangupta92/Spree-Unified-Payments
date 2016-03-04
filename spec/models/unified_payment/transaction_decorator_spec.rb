require 'spec_helper'

describe UnifiedPayment::Transaction do
  it { is_expected.to belong_to(:user).class_name('Spree::User') }
  it { is_expected.to belong_to(:order).class_name('Spree::Order') }

  it { is_expected.to have_one(:store_credit).class_name('Spree::StoreCredit') }
  let(:order) { mock_model(Spree::Order) }
  let(:user) { mock_model(Spree::User) }

  before do
    allow_any_instance_of(UnifiedPayment::Transaction).to receive(:assign_attributes_using_xml).and_return(true)
    allow_any_instance_of(UnifiedPayment::Transaction).to receive(:notify_user_on_transaction_status).and_return(true)
    allow_any_instance_of(UnifiedPayment::Transaction).to receive(:complete_order).and_return(true)
    allow_any_instance_of(UnifiedPayment::Transaction).to receive(:cancel_order).and_return(true)
    allow_any_instance_of(UnifiedPayment::Transaction).to receive(:wallet_transaction).and_return(true)
    allow_any_instance_of(UnifiedPayment::Transaction).to receive(:enqueue_expiration_task).and_return(true)
    allow_any_instance_of(UnifiedPayment::Transaction).to receive(:release_order_inventory).and_return(true)
    allow_any_instance_of(UnifiedPayment::Transaction).to receive(:payment_valid_for_order?).and_return(true)
  end

  context 'callbacks' do
    context 'after and before save' do
      context 'pending transaction on creation' do
        before do
          @pending_card_transaction = UnifiedPayment::Transaction.new(:status => 'pending', :payment_transaction_id => '1234', :amount => 100)
        end

        it { expect(@pending_card_transaction).not_to receive(:notify_user_on_transaction_status) }
        it { expect(@pending_card_transaction).not_to receive(:assign_attributes_using_xml) }
        it { expect(@pending_card_transaction).not_to receive(:complete_order) }
        it { expect(@pending_card_transaction).not_to receive(:cancel_order) }
        it { expect(@pending_card_transaction).not_to receive(:wallet_transaction) }
        it { expect(@pending_card_transaction).not_to receive(:release_order_inventory) }

        after do
          @pending_card_transaction.save!
        end
      end

      context 'pending to successful transaction' do
        before do
          @successful_card_transaction = UnifiedPayment::Transaction.new(:status => 'pending', :payment_transaction_id => '1234', :amount => 100)
          @successful_card_transaction.save!
          @successful_card_transaction.status = 'successful'
        end

        it { expect(@successful_card_transaction).to receive(:notify_user_on_transaction_status).and_return(true) }
        it { expect(@successful_card_transaction).to receive(:assign_attributes_using_xml).and_return(true) }
        it { expect(@successful_card_transaction).not_to receive(:release_order_inventory) }

        context 'order inventory released' do
          before do
            allow(@successful_card_transaction).to receive(:order_inventory_released?).and_return(true)
          end

          context 'payment valid for order' do
            it { expect(@successful_card_transaction).to receive(:wallet_transaction).and_return(true) }
            it { expect(@successful_card_transaction).not_to receive(:complete_order) }
            it { expect(@successful_card_transaction).not_to receive(:cancel_order) }
          end

          context 'payment not valid for order' do
            before { allow(@successful_card_transaction).to receive(:payment_valid_for_order?).and_return(false) }

            it { expect(@successful_card_transaction).to receive(:wallet_transaction).and_return(true) }
            it { expect(@successful_card_transaction).not_to receive(:complete_order) }
            it { expect(@successful_card_transaction).not_to receive(:cancel_order) }
          end
        end
        
        context 'order inventory not released and' do
          before { allow(@successful_card_transaction).to receive(:order_inventory_released?).and_return(false) }
          context 'payment valid for order' do
            it { expect(@successful_card_transaction).to receive(:complete_order).and_return(true) }
            it { expect(@successful_card_transaction).not_to receive(:wallet_transaction) }
          end

          context 'payment not valid for order' do
            before { allow(@successful_card_transaction).to receive(:payment_valid_for_order?).and_return(false) }
            it { expect(@successful_card_transaction).to receive(:wallet_transaction).and_return(true) }
            it { expect(@successful_card_transaction).not_to receive(:complete_order) }
          end
         end
        
        after do
          @successful_card_transaction.save!
        end
      end

      context 'pending to unsuccessful transaction' do
        before do
          @unsuccessful_card_transaction = UnifiedPayment::Transaction.new(:status => 'pending', :payment_transaction_id => '1234', :amount => 100)
          @unsuccessful_card_transaction.save!
          @unsuccessful_card_transaction.status = 'unsuccessful'
        end

        context 'order inventory released' do
          before do
            allow(@unsuccessful_card_transaction).to receive(:order_inventory_released?).and_return(true)
          end
          it { expect(@unsuccessful_card_transaction).not_to receive(:complete_order) }
        end

        it { expect(@unsuccessful_card_transaction).to receive(:notify_user_on_transaction_status).and_return(true) }
        it { expect(@unsuccessful_card_transaction).to receive(:assign_attributes_using_xml).and_return(true) }
        it { expect(@unsuccessful_card_transaction).not_to receive(:complete_order) }
        it { expect(@unsuccessful_card_transaction).to receive(:cancel_order).and_return(true) }
        it { expect(@unsuccessful_card_transaction).not_to receive(:release_order_inventory) }

        after do
          @unsuccessful_card_transaction.save!
        end
      end

      context 'expire transaction' do
        before do
          @pending_card_transaction = UnifiedPayment::Transaction.create!(:status => 'pending', :payment_transaction_id => '1234', :amount => 100)
          @expired_card_transaction = UnifiedPayment::Transaction.create!(:status => 'unsuccessful', :payment_transaction_id => '1234', :amount => 100)
          @expired_card_transaction.expired_at = Time.current
          @expired_card_transaction.save!
        end

        it 'should not call release_order_inventory when not expiring a card transaction' do
          expect(@pending_card_transaction).not_to receive(:release_order_inventory)
          @pending_card_transaction.update_attribute(:status, :successful)
        end

        it 'should not call release_order_inventory for expiring expired card transaction' do
          expect(@expired_card_transaction).not_to receive(:release_order_inventory)
          @expired_card_transaction.update_attribute(:expired_at, Time.now)
        end

        it 'should call release_order_inventory for expiring pending card transaction' do
          expect(@pending_card_transaction).to receive(:release_order_inventory).and_return(true)
          @pending_card_transaction.update_attribute(:expired_at, Time.now)
        end
      end
    end
  end

  context 'scopes' do
    describe 'pending' do
      before do
        @successful_card_transaction = UnifiedPayment::Transaction.create!(:status => 'successful', :payment_transaction_id => '1234', :amount => 100)
        @pending_card_transaction = UnifiedPayment::Transaction.create!(:status => 'pending', :payment_transaction_id => '1234', :amount => 100)
      end

      it { expect(UnifiedPayment::Transaction.pending).to eq([@pending_card_transaction]) }
    end
  end

  describe '#order_inventory_released?' do
    before(:all) do 
      @expired_card_transaction = UnifiedPayment::Transaction.new
      @expired_card_transaction.expired_at = Time.now
      @pending_card_transaction = UnifiedPayment::Transaction.new
    end
    
    it { expect(@expired_card_transaction.order_inventory_released?).to be_truthy }
    it { expect(@pending_card_transaction.order_inventory_released?).to be_falsey }
  end

  describe '#assign_attributes_using_xml' do
    before do
      allow_any_instance_of(UnifiedPayment::Transaction).to receive(:assign_attributes_using_xml).and_call_original
      @card_transaction_with_message = UnifiedPayment::Transaction.create!(:payment_transaction_id => '123321', :amount => 100)
      @xml_response = '<Message><PAN>123XXX123</PAN><PurchaseAmountScr>200</PurchaseAmountScr><Currency>NGN</Currency><ResponseDescription>TestDescription</ResponseDescription><OrderStatus>OnTest</OrderStatus><OrderDescription>TestOrder</OrderDescription><Status>00</Status><MerchantTranID>12345654321</MerchantTranID><ApprovalCode>123ABC</ApprovalCode></Message>'
      allow(@card_transaction_with_message).to receive(:xml_response).and_return(@xml_response)
      @gateway_transaction = UnifiedPayment::Transaction.new
      allow(@card_transaction_with_message).to receive(:gateway_transaction).and_return(@gateway_transaction)
      @card_transaction_without_message = UnifiedPayment::Transaction.new
    end

    describe 'method calls' do
      it { expect(@card_transaction_with_message).to receive(:xml_response).and_return(@xml_response) }
      it { expect(@xml_response).to receive(:include?).with('<Message').and_return(true) } 
        
      after do
        @card_transaction_with_message.send(:assign_attributes_using_xml)
      end
    end

    describe 'assigns' do
      before { @card_transaction_with_message.send(:assign_attributes_using_xml) }
      it { expect(@card_transaction_with_message.pan).to eq('123XXX123') }
      it { expect(@card_transaction_with_message.response_description).to eq('TestDescription') }
      it { expect(@card_transaction_with_message.gateway_order_status).to eq('OnTest') }
      it { expect(@card_transaction_with_message.order_description).to eq('TestOrder') }
      it { expect(@card_transaction_with_message.response_status).to eq('00') }
      it { expect(@card_transaction_with_message.approval_code).to eq('123ABC') }
      it { expect(@card_transaction_with_message.merchant_id).to eq('12345654321') }
    end
  end

  describe '#notify_user_on_transaction_status' do
    before do
      allow_any_instance_of(UnifiedPayment::Transaction).to receive(:notify_user_on_transaction_status).and_call_original
      @card_transaction = UnifiedPayment::Transaction.new(:status => 'pending', :payment_transaction_id => '1234', :amount => 100)
      @mailer_object = Object.new
      allow(@mailer_object).to receive(:deliver!).and_return(true)
      allow(Spree::TransactionNotificationMailer).to receive(:delay).and_return(Spree::TransactionNotificationMailer)
      allow(Spree::TransactionNotificationMailer).to receive(:send_mail).with(@card_transaction).and_return(@mailer_object)
    end

    context 'when previous state was not pending' do
      it { expect(Spree::TransactionNotificationMailer).not_to receive(:send_mail) }
    end

    context 'when previous state was pending' do
      before do
        @card_transaction.save!
        @card_transaction.status = 'successful'
      end

      it { expect(Spree::TransactionNotificationMailer).to receive(:delay).and_return(Spree::TransactionNotificationMailer) }
      it { expect(Spree::TransactionNotificationMailer).to receive(:send_mail).with(@card_transaction).and_return(@mailer_object) }
    end
    
    after do
      @card_transaction.save!
    end
  end

  describe '#complete_order' do
    before do
      allow_any_instance_of(UnifiedPayment::Transaction).to receive(:complete_order).and_call_original
      @card_transaction = UnifiedPayment::Transaction.new(:status => 'successful', :payment_transaction_id => '1234', :amount => '100')
      allow(@card_transaction).to receive(:order).and_return(order)
      allow(order).to receive(:next!).and_return(true)
      @payment = mock_model(Spree::Payment)
      allow(@payment).to receive(:complete).and_return(true)
      allow(order).to receive(:pending_payments).and_return([@payment])
      allow(order).to receive(:total).and_return(100)
    end

    it { expect(order).to receive(:next!).and_return(true) }
    it { expect(order).to receive(:pending_payments).and_return([@payment]) }
    it { expect(@payment).to receive(:complete).and_return(true) }
    
    after do
      @card_transaction.send(:complete_order)
    end
  end

  describe '#cancel_order' do
    before do
      allow_any_instance_of(UnifiedPayment::Transaction).to receive(:cancel_order).and_call_original
      @card_transaction = UnifiedPayment::Transaction.new(:status => 'unsuccessful', :payment_transaction_id => '1234', :amount => 100)
      allow(@card_transaction).to receive(:order).and_return(order)
      allow(order).to receive(:release_inventory).and_return(true)
      @payment = mock_model(Spree::Payment)
      allow(@payment).to receive(:update_attribute).with(:state, 'failed').and_return(true)
      allow(order).to receive(:pending_payments).and_return([@payment])
    end

    context 'when order is completed' do
      before do
        allow(order).to receive(:completed?).and_return(true)
      end

      it { expect(order).not_to receive(:release_inventory) }
      it { expect(order).not_to receive(:pending_payments) }
    
      after do
        @card_transaction.send(:cancel_order)
      end
    end

    context 'when order is not completed' do
      before do
        allow(order).to receive(:completed?).and_return(false)
      end

      context 'inventory released' do
        before { allow(@card_transaction).to receive(:order_inventory_released?).and_return(true) }
        it { expect(order).not_to receive(:release_inventory) }
      end

      context 'inventory not released' do
        it { expect(order).to receive(:release_inventory).and_return(true) }
      end

      it { expect(order).to receive(:pending_payments).and_return([@payment]) }
      it { expect(@payment).to receive(:update_attribute).with(:state, 'failed').and_return(true) }
      
      after do
        @card_transaction.send(:cancel_order)
      end
    end
  end
  
  describe '#release_order_inventory' do
    before do
      allow_any_instance_of(UnifiedPayment::Transaction).to receive(:release_order_inventory).and_call_original
      @order = mock_model(Spree::Order)
      allow(@order).to receive(:release_inventory).and_return(true)
      @card_transaction = UnifiedPayment::Transaction.new(:status => 'somestatus')
      allow(@card_transaction).to receive(:order).and_return(@order)
    end

    context 'when order is already completed' do
      before { allow(@order).to receive(:completed?).and_return(true) }
      it { expect(@order).not_to receive(:release_inventory) }
    end

    context 'when order is not completed' do
      before { allow(@order).to receive(:completed?).and_return(false) }
      it { expect(@order).to receive(:release_inventory) }
    end

    after do
      @card_transaction.send(:release_order_inventory)
    end
  end

  describe 'abort!' do
    before do
      @time_now = DateTime.strptime('2012-03-03', '%Y-%m-%d')
      allow(Time).to receive(:current).and_return(@time_now)
      @card_transaction = UnifiedPayment::Transaction.new(:status => 'somestatus', :payment_transaction_id => '1234', :amount => 100)
      allow(@card_transaction).to receive(:release_order_inventory).and_return(true)
    end

    it 'release inventory' do
      expect(@card_transaction).to receive(:release_order_inventory).and_return(true)
      @card_transaction.abort!
    end

    it 'assigns expired_at' do
      @card_transaction.abort!
      expect(@card_transaction.reload.expired_at).to eq(@time_now.to_s)
    end
  end

  describe 'status checks for pening, unsuccessful and successful' do
    before do
      @successful_card_transaction = UnifiedPayment::Transaction.create!(:status => 'successful', :payment_transaction_id => '1234', :amount => 100)
      @pending_card_transaction = UnifiedPayment::Transaction.create!(:status => 'pending', :payment_transaction_id => '1234', :amount => 100)
      @unsuccessful_card_transaction = UnifiedPayment::Transaction.create!(:status => 'unsuccessful', :payment_transaction_id => '1234', :amount => 100)
    end

    it { expect(@successful_card_transaction.pending?).to be_falsey }
    it { expect(@successful_card_transaction.successful?).to be_truthy }
    it { expect(@successful_card_transaction.unsuccessful?).to be_falsey }

    it { expect(@unsuccessful_card_transaction.successful?).to be_falsey }
    it { expect(@unsuccessful_card_transaction.pending?).to be_falsey }
    it { expect(@unsuccessful_card_transaction.unsuccessful?).to be_truthy }

    it { expect(@pending_card_transaction.pending?).to be_truthy } 
    it { expect(@pending_card_transaction.successful?).to be_falsey } 
    it { expect(@pending_card_transaction.unsuccessful?).to be_falsey } 
  end

  describe '#enqueue_expiration_task' do
    before do
      allow_any_instance_of(UnifiedPayment::Transaction).to receive(:enqueue_expiration_task).and_call_original
      @last_id = UnifiedPayment::Transaction.last.try(:id) || 0
      current_time = Time.current
      allow(Time).to receive(:current).and_return(current_time)
      @new_card_transaction = UnifiedPayment::Transaction.new(:status => 'pending')
      allow(@new_card_transaction).to receive(:id).and_return(123)
    end
    
    context 'when transaction id is present' do
      before { @new_card_transaction.payment_transaction_id = '1234' }
      it 'enqueue delayed job' do
        expect(Delayed::Job).to receive(:enqueue).with(TransactionExpiration.new(@new_card_transaction.id), { :run_at => TRANSACTION_LIFETIME.minutes.from_now }).and_return(true)
      end

      after do
        @new_card_transaction.save!
      end
    end

    context 'when transaction id is not present' do
      it 'does not enqueue delayed job' do
        expect(Delayed::Job).not_to receive(:enqueue).with(TransactionExpiration.new(@new_card_transaction.id), { :run_at => TRANSACTION_LIFETIME.minutes.from_now })
      end

      after do
        @new_card_transaction.save!
      end
    end
  end

  describe '#wallet_transaction' do
    before do
      allow_any_instance_of(UnifiedPayment::Transaction).to receive(:wallet_transaction).and_call_original
      @card_transaction = UnifiedPayment::Transaction.create!(:payment_transaction_id => '123454321', :amount => 200)
      allow(@card_transaction).to receive(:user).and_return(user)
      allow(@card_transaction).to receive(:order).and_return(order)
      allow(user).to receive(:store_credits_total).and_return(100)
      @store_credit_balance = user.store_credits_total + @card_transaction.amount.to_f
      @store_credit = Object.new
      allow(@card_transaction).to receive(:build_store_credit).with(:balance => @store_credit_balance, :user => user, :transactioner => user, :amount => @card_transaction.amount.to_f, :reason => "transferred from transaction:#{@card_transaction.payment_transaction_id}", :payment_mode => Spree::Credit::PAYMENT_MODE['Payment Refund'], :type => "Spree::Credit").and_return(@store_credit)
      allow(@store_credit).to receive(:save!).and_return(true)
    end

    it { expect(@card_transaction).to receive(:build_store_credit).with(:balance => @store_credit_balance, :user => user, :transactioner => user, :amount => @card_transaction.amount.to_f, :reason => "transferred from transaction:#{@card_transaction.payment_transaction_id}", :payment_mode => Spree::Credit::PAYMENT_MODE['Payment Refund'], :type => "Spree::Credit").and_return(@store_credit) }
    it { expect(user).to receive(:store_credits_total).and_return(100) }
    it { expect(@store_credit).to receive(:save!).and_return(true) }
    it { expect(@card_transaction).not_to receive(:associate_user) }
    
    context 'when user is nil' do
      before { allow(user).to receive(:nil?).and_return(true) }
      
      it { expect(@card_transaction).to receive(:associate_user).and_return(true) }
    end
    
    after do
      @card_transaction.wallet_transaction
    end
  end

  describe '#associate_user' do
    before do
      @card_transaction = UnifiedPayment::Transaction.create!(:payment_transaction_id => '123454321', :amount => 100)
      allow(@card_transaction).to receive(:order).and_return(order)
      allow(order).to receive(:email).and_return('test_user@baloo.com')
      allow(@card_transaction).to receive(:save!).and_return(true)
      @new_user = mock_model(Spree::User)
    end

    context 'when user with the order email exists' do
      before do 
        allow(Spree::User).to receive(:where).with(:email => order.email).and_return([user])
        allow(@card_transaction).to receive(:user=).with(user).and_return(true)
      end
      
      describe 'method calls' do
        it { expect(Spree::User).to receive(:where).with(:email => order.email).and_return([user]) }
        it { expect(@card_transaction).to receive(:user=).with(user).and_return(true) }
        after do
          @card_transaction.send(:associate_user)
        end
      end
    end

    context 'when user with the order email does not exist' do
      before do
        allow(Spree::User).to receive(:where).with(:email => order.email).and_return([]) 
        allow(Spree::User).to receive(:create_unified_transaction_user).with(order.email).and_return(user)
      end

      describe 'method calls' do
        it { expect(Spree::User).to receive(:where).with(:email => order.email).and_return([]) }
        it { expect(Spree::User).to receive(:create_unified_transaction_user).with(order.email).and_return(user) }
        
        after do
          @card_transaction.send(:associate_user)
        end
      end

      it 'associates a new user' do
        expect(@card_transaction.user).to be_nil
        @card_transaction.send(:associate_user)
        expect(@card_transaction.user).to eq(user)
      end
    end
  end

  describe '#update_transaction_on_query' do
    before { @card_transaction = UnifiedPayment::Transaction.create!(:payment_transaction_id => '123454321', :amount => 100) }
    
    context 'status is APPROVED' do
      it { expect(@card_transaction).to receive(:assign_attributes).with(:gateway_order_status => 'APPROVED', :status => 'successful').and_return(true) }
      it { expect(@card_transaction).to receive(:save).with(:validate => false).and_return(true) }
      after { @card_transaction.update_transaction_on_query('APPROVED') }
    end

    context 'status is APPROVED' do
      it { expect(@card_transaction).to receive(:assign_attributes).with(:gateway_order_status => 'MyStatus').and_return(true) }
      it { expect(@card_transaction).to receive(:save).with(:validate => false).and_return(true) }
      after { @card_transaction.update_transaction_on_query('MyStatus') }
    end
  end
end