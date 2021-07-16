#!/usr/local/bin/env python3
from builtins import input

import boto3
import sys
import json
import re

#### ensure you have python3 and pip3 installed
#### install all necessary imports - eg. 'pip3 install boto3 --user'
#### usage: saml2aws exec --exec-profile  -- <aws role> python3 dynamodb_copy_table_items.py <tableArn> <read/write>

table_arn = sys.argv[1]
action = sys.argv[2]

# arn:aws:dynamodb:us-east-1:403959985054:table/OfferAffiliateConfiguration
aws_account = re.split(":", table_arn)[4]

if aws_account == "403959985054" and action == "write":
    print("You should not write content to a production database.  Please try again")
    exit()

table_name = re.split(":/", table_arn)[-1]

table_name_check = input("Are you sure you want to {0} the {1} table? (Y/N) ".format(action, table_name))
if table_name_check == "N":
    exit()

# scan source dynamodb table & write to file
if action == "read":
    src_client = boto3.client('dynamodb')

    dynamo_items = []
    api_response = src_client.scan(TableName=table_name, Select='ALL_ATTRIBUTES')
    dynamo_items.extend(api_response['Items'])
    print("Collected total {0} items from table {1}".format(len(dynamo_items), table_name))

    while 'LastEvaluatedKey' in api_response:
        api_response = src_client.scan(TableName=table_name,
                                       Select='ALL_ATTRIBUTES',
                                       ExclusiveStartKey=api_response['LastEvaluatedKey'])
        dynamo_items.extend(api_response['Items'])
        print("Collected total {0} items from table {1}".format(len(dynamo_items), table_name))

    with open('results.json', 'w') as outfile:
        json.dump(dynamo_items, outfile)

# read objects from a file and write to dynamodb destination table
elif action == "write":
    dynamodb = boto3.client('dynamodb')

    batched_records = []
    with open('results.json') as result:
        json_records = json.load(result)

        i = 0
        for record in json_records:
            batched_records.append({'PutRequest': { 'Item': record }})

            if len(batched_records) == 25:
                dynamodb.batch_write_item(RequestItems={table_name: batched_records })
                print("Sent batch successfully")
                batched_records.clear()
                i += 25
            else:
                continue

        if len(batched_records) > 0:
            dynamodb.batch_write_item(RequestItems={table_name: batched_records })
            i += len(batched_records)

    print("Added {0} records to {1}".format(i, table_name))
else:
    print("The only valid actions are read or write.")



