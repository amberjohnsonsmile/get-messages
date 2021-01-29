require "aws-sdk"
require "json"
require "pry"

#
# This script pulls all the messages from an SQS queue and saves them to a json file.
#
# To run the script:
#   1. Install ruby
#   2. Run `bundle install`
#   3. Use the proper profile to run the script and pass in the queue url:
#      saml2aws exec --exec-profile <profile> -- ruby get_messages.rb <queue-url>
#
class GetMessages

  def self.get_messages
    queue_url = ARGV[0]
    if ARGV[0].nil?
      puts "Please pass in the queue URL as an argument"
      return
    end

    processed_messages = []
    messages = receive_messages(queue_url)

    while !messages.empty?
      messages.each do |message|
        puts "Processing message with id #{message.message_id}"

        # If it is json, minify it
        if valid_json?(message.body)
          message.body = JSON.parse(message.body).to_json
        else
          message.body = "\"#{message.body}\""
        end

        processed_messages.push(message.body + ",")
      end
      messages = receive_messages(queue_url)
    end

    if processed_messages.empty?
      puts "There are 0 messages in the queue, or the queue's visibility timeout (usually 5 minutes) has not expired"
      return
    end

    # Manual formatting so each message gets its own line but the whole thing is still valid json
    processed_messages[0] = "[" + processed_messages[0]
    processed_messages[processed_messages.size - 1] = processed_messages[processed_messages.size - 1].chop + "]"

    filename = "messages-#{Time.now.strftime("%Y-%m-%dT%H:%M:%S")}.json"
    File.open(filename, "w+") do |f|
      f.puts(processed_messages)
      puts "\n#{processed_messages.size} messages saved to file:\n#{filename}"
    end
  end

  def self.receive_messages(queue_url)
    response = client.receive_message(
      queue_url: queue_url,
      attribute_names: ["All"],
      max_number_of_messages: 10,
      wait_time_seconds: 1
    )
    response.data.messages
  end

  def self.client
    @client ||= Aws::SQS::Client.new
  end

  def self.valid_json?(string)
    begin
      JSON.parse(string)
      return true
    rescue JSON::ParserError => e
      return false
    end
  end
end

GetMessages.get_messages
