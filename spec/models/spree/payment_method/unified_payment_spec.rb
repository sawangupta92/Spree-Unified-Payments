require 'spec_helper'

describe Spree::PaymentMethod::UnifiedPaymentMethod do
  let(:pending_payment) { mock_model(Spree::Payment, :state => 'pending') }
  let(:complete_payment) { mock_model(Spree::Payment, :state => 'complete') }
  let(:void_payment) { mock_model(Spree::Payment, :state => 'void') }
  before { @unified_payment = Spree::PaymentMethod::UnifiedPaymentMethod.new }
  it { expect(@unified_payment.actions).to eq(["capture", "void"]) }
  it { expect(@unified_payment.can_capture?(pending_payment)).to be_truthy }
  it { expect(@unified_payment.can_capture?(complete_payment)).to be_falsey }
  it { expect(@unified_payment.can_void?(pending_payment)).to be_truthy }
  it { expect(@unified_payment.can_void?(void_payment)).to be_falsey }
  it { expect(@unified_payment.source_required?).to be_falsey }
  it { expect(@unified_payment.payment_profiles_supported?).to be_truthy }

  it 'voids a payment' do
    expect(ActiveMerchant::Billing::Response).to receive(:new).with(true, "", {}, {}).and_return(true)
    @unified_payment.void
  end

  it 'captures a payment' do
    expect(ActiveMerchant::Billing::Response).to receive(:new).with(true, "", {}, {}).and_return(true)
    @unified_payment.capture
  end
end