#!/bin/bash

# Use this script to purge Affiliate Integration webhook queues and DLQs in either staging or production
# Example: saml2aws exec --exec-profile affiliate-integration-admin-stage --
#               scripts/purge-dlq.sh dl-impact-radius-adapter-webhooks.fifo

set -o errexit

echo "Retrieving queue-url for queue-name: $1"
queue_url=$(aws sqs get-queue-url --queue-name $1 | jq -r ".QueueUrl")

if [[ $queue_url == "" ]]
then
    echo "This user does not have access to $1"
    exit 0

else
    read -p "Purge queue $queue_url? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        aws sqs purge-queue --queue-url $queue_url
    else
        exit 0
    fi
fi