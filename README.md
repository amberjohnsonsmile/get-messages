Get Messages

This script pulls all the messages from an SQS queue and saves them to a json file.
Clone this repo and follow the instructions below.

To run the script:
  1. Install ruby
  2. Run `bundle install`
  3. Use the proper profile to run the script and pass in the queue url:
     `saml2aws exec --exec-profile <profile> -- ruby get_messages.rb "queue-url"`
