require 'spec_helper'

describe 'Constants' do
  it { expect(UNIFIED_XML_CONTENT_MAPPING).to eq({ :masked_pan => 'PAN', :customer_name => 'Name', 
    :transaction_date_and_time => 'TranDateTime', :transaction_amount => 'PurchaseAmountScr', 
    :transaction_currency => 'CurrencyScr', :approval_code => 'ApprovalCode'}) }
  it { expect(TRANSACTION_LIFETIME).to eq 5 }
end
