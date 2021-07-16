import boto3
import gzip
import json
import http.client
import sys

# to run saml2aws exec --exec-profile -- <saml-profile>
#   python3 get_objects.py <month> <start_day> <end_day> <x-button-test-signature secret>
# eg: saml2aws exec --exec-profile  -- monolith python3 get_objects.py 04 01 30 abcd12345
# The x-button-test-signature value that is used as auth for the Button Adapter can be found in LastPass

class GetObjects:

    @classmethod
    def get_objects(cls):
        s3 = boto3.client('s3')
        month = sys.argv[1]
        start_day = int(sys.argv[2])
        end_day = int(sys.argv[3])
        secret = sys.argv[4]

        i = start_day
        while i <= end_day:
            day = f'0{i}' if i < 10 else i
            object_names = s3.list_objects_v2(
                Bucket='ibotta-kinesis-firehose',
                Prefix=f'button-webhooks/2021/{month}/{day}/'
            )
            key_names = object_names['Contents']

            for name in key_names:
                trxn_data = cls.grab_objects_by_key(cls, name['Key'], s3)
                cls.send_transactions(trxn_data, secret)

            i += 1

    def grab_objects_by_key(self, key, s3):
        compressed_object = s3.get_object(Bucket='ibotta-kinesis-firehose', Key=key)['Body'].read()
        try:
            result = gzip.decompress(compressed_object)
            formatted_data = self.format_json(result)
            return json.loads(formatted_data)
        except:
            print(f"Exception thrown decompressing & formatting data for {compressed_object}")

    def format_json(decompressed_result):
        decoded_string = decompressed_result.decode('utf-8')
        array_fomat = "[" + decoded_string + "]"
        csv = array_fomat.replace('\n', ',')
        final_data = csv.replace('},]', '}]')
        return final_data

    def send_transactions(trxn_data, secret):
        for trxn in trxn_data:
            try:
                json_data = json.dumps(trxn)
                conn = http.client.HTTPSConnection("api.ibops.net")
                payload = json_data
                headers = {
                  'x-button-test-signature': secret
                }
                conn.request("POST", "/button-adapter/button_webhook", payload, headers)
                res = conn.getresponse()
                data = res.read()
                print(data.decode("utf-8"))
            except:
                print(f'Exception thrown sending to endpoint for trxn: {trxn}')


GetObjects.get_objects()
