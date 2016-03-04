module Spree
  class TransactionNotificationMailer < ActionMailer::Base
    helper 'transaction_notification_mail'
    # helper 'application'
    default from: :admin_email

    def send_mail(card_transaction)
      @card_transaction = card_transaction
      @message = @card_transaction.xml_response.include?('<Message') ? Hash.from_xml(@card_transaction.xml_response)['Message'] : {}
      mail(
        :to => @card_transaction.user.email,
        :subject => "#{Spree::Store.first.name} - Unified Payment Transaction #{@card_transaction.status} notification"
      )
    end

    def admin_email
      Spree::Store.first.email
    end
  end
end
