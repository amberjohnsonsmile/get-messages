require "aws-sdk"
require "base64"
require "date"
require "json"
require "pry"
require "zlib"
require "stringio"

#
# This script pulls all the messages from an SQS queue and saves them to a json file.
#
# To run the script:
#   1. Install ruby
#   2. Run `bundle install`
#   3. Use the proper profile to run the script and pass in the queue url:
#      saml2aws exec --exec-profile <profile> -- ruby get_messages.rb "queue-url"
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
        processed_messages.push(JSON.parse(message.body))
      end
      messages = receive_messages(queue_url)
    end

    if processed_messages.empty?
      puts "There are 0 messages in the queue, or the queue's visibility timeout (usually 5 minutes) has not expired"
      return
    end

    filename = "messages-#{Time.now.strftime("%Y-%m-%dT%H:%M:%S")}.json"
    File.open(filename, "w+") do |f|
      f.write(JSON.pretty_generate(processed_messages))
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

end

GetMessages.get_messages
