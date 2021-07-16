# This script is designed to be run from tools. You can either validate or cancel receipts.
#
# CSV Required Format
# Field               | Field Name
# --------------------|--------------------
# Receipt Id          | receipt_id
# Transaction Id      | transaction_id
# Customer Id         | customer_id
# Retailer Id         | retailer_id
# Transaction Status  | button_log_txn_status
# Commission Total    | receipt_commission_total
#
#
# To run:
#
# Copy the csv file to tools
# > scp <path to file/filename.csv> tools.ibotta.com:/tmp/button_purchases.csv
#
# From tools, kick off the script
# > ssh tools.ibotta.com
# > ibotta_app_user
# > ibotta_current
# > bin/rails c
# > <copy the script into the console>
# > ProcessReceipts.process_validated/process_canceled
#
# After the script has finished, a new file will be saved in the /tmp directory.
# Download this file to use with the EmitEvents script.
# > scp tools.ibotta.com:tmp/acnes-<datetime>.json dir/to/save/to/acne_events
# To emit the ACNE events run ProcessReceipts.emit

require 'ibotta_pb/rewards/events_pb'

class ProcessReceipts
  # This is the production endpoint
  SNS_TOPIC = "arn:aws:sns:us-east-1:403959985054:affiliate-commission-notified-events"

  def self.process_validated
    rows = read_csv("/tmp/receipts.csv")
    rows.each do |row|
      puts "Validating receipt_id: #{row["receipt_id"]}"
      receipt = validate_receipt(row["receipt_id"])
      save_acnes(row, receipt)
    end
  end

  def self.process_canceled
    rows = read_csv("/tmp/receipts.csv")
    rows.each do |row|
      receipt = cancel_receipt(row["receipt_id"])
      save_acnes(row, receipt)
    end
  end

  def self.gather_acnes
    rows = read_csv("/tmp/button_purchases.csv")
    rows.each do |row|
      receipt = Receipt.find(row["receipt_id"])
      save_acnes(row, receipt)
    end
  end

  def self.validate_receipt(receipt_id)
    r = Receipt.where(id: receipt_id).first
    if receipt.processing_state != "tlog_pending"
      r.processing_state = "tlog_pending"
      r.save!
    end
    MCommWorkerSerial.enqueue(r.id, r.customer_id, :process_validated, false)
    r
  end

  def self.cancel_receipt(receipt_id)
    puts "Canceling receipt_id: #{receipt_id}"
    r = Receipt.find(receipt_id)
    MCommWorkerSerial.enqueue(r.id, r.customer_id, :process_canceled, false)
    r
  end

  def self.read_csv(file_location)
    csv = CSV.read(file_location)
    keys = csv.shift
    csv.map {|row| Hash[ keys.zip(row) ] }
  end

  def self.save_acnes(row, receipt)
    filename = "/tmp/acnes-#{Time.now.strftime("%Y-%m-%dT%H:%M:%S")}.json"
    events = []
    if !receipt.receipt_items.empty?
      receipt.receipt_items.each do |item|
        event = build_acne(row, receipt, item)
        events << event.to_h.to_json
      end
    else
      event = build_acne(row, receipt, nil)
      events << event.to_h.to_json
    end

    File.open(filename, 'a') do |file|
      file.puts(events)
    end
  end

  def self.build_acne(row, receipt, item)
    # Leave event defined separately so we can pass it in to build_event_header
    event = IbottaPb::Accounting::AffiliateCommissionNotifiedEvent.new
    event.event_header = build_event_header(event)
    event.affiliateCommission = build_ac(row, receipt, item)
    event
  end

  def self.build_event_header(event)
    IbottaPb::System::EventHeader.new(
      event_uri:    IPB::URI::Ibotta.for_proto(event.class),
      event_at:     IPB::Time.to_proto(Time.now),
      environment:  SEB::Config.environment_proto,
      agent:        SEB::Config.agent_name,
      host:         Ibotta::Env.instance.hostname,
      revision:     Ibotta::Env.instance.version,
      fake:         false,
      )
  end

  def self.build_ac(row, receipt, item)
    now = IbottaPb::Commons::Timestamp.new(millis: DateTime.now.strftime('%Q').to_i)
    IbottaPb::Accounting::AffiliateCommissionNotified.new(
      commission: build_commission(row, receipt, item, now),
      purchase_uri: uri("BUTTON", "ibotta_pb.purchase.Purchase", row["transaction_id"]),
      sku: item&.raw_product_number ? item.raw_product_number : "",
      transaction_id: row["transaction_id"],
      commission_created_at: now,
      calculated_commission: false,
      platform: 'UNKNOWN_PLATFORM',
      )
  end

  def self.build_commission(row, receipt, item, now)
    IbottaPb::Accounting::Commission.new(
      state: row["button_log_txn_status"] == "finalized" ? "FINALIZED" : "DECLINED",
      source_uri: uri("BUTTON", "Order", row["transaction_id"]),
      shopper_uri: uri("IB_MON", "Customer", row["customer_id"]),
      retailer_uri: uri("IB_MON", "Retailer", row["retailer_id"]),
      reported_at: now,
      finalized_at: row["button_log_txn_status"] == "finalized" ? now : nil,
      declined_at: row["button_log_txn_status"] == "finalized" ? nil : now,
      modified_at: now,
      receivable_amount: money(row["receipt_commission_total"].to_f),
      other_uris: [],
      )
  end

  def self.uri(dom, type, id)
    IbottaPb::System::URI.new(
      dom:  dom,
      type: type,
      id:   id
    )
  end

  def self.money(amount)
    micros = Ibotta::MoneyUtil.to_micros(amount)
    IbottaPb::Money::Money.new(micros: micros, currency: "USD")
  end

  def self.emit
    counter = 1

    File.open("acnes.json", "r") do |f|
      f.each_line { |line|
        success = sns_topic.publish({
                                      message: line
                                    })

        if success.message_id.empty?
          puts "Error emitting event: #{line}"
        end
        puts "processed #{counter} events"

        counter += 1
      }
    end
  end

  def self.sns_topic
    @sns_topic ||= Aws::SNS::Resource.new(region: 'us-east-1').topic(SNS_TOPIC)
  end

end