module TransactionNotificationMailHelper
  def mail_content_hash_for_unified(info_hash, card_transaction)
    send_info = {}
    
    UNIFIED_XML_CONTENT_MAPPING.each_pair { |key, value| send_info[key] = info_hash[value] }
    
    send_info[:transaction_reference] = card_transaction.payment_transaction_id
    send_info[:merchants_name] = Spree::Store.first.name
    send_info[:merchants_url] = Spree::Store.first.url
    send_info
  end
end
