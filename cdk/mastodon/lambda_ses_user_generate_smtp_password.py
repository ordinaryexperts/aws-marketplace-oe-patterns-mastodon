import base64
import boto3
import cfnresponse
import hashlib
import hmac
import json
import traceback
from botocore.exceptions import ClientError

def sign(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()

def handler(event, context):
    try:
        if event["RequestType"] == "Delete":
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            return
        key    = event["ResourceProperties"]["secret_access_key"]
        region = event["ResourceProperties"]["aws_region"]
        stack  = event["ResourceProperties"]["stack_name"]
        user   = event["ResourceProperties"]["access_key_id"]

        date     = "11111111"
        service  = "ses"
        message  = "SendRawEmail"
        terminal = "aws4_request"
        version  = 0x04

        signature = sign(("AWS4" + key).encode("utf-8"), date)
        signature = sign(signature, region)
        signature = sign(signature, service)
        signature = sign(signature, terminal)
        signature = sign(signature, message)
        signature_and_version = bytes([version]) + signature
        smtp_password = base64.b64encode(signature_and_version).decode("utf-8")

        secret = { "username": user, "password": smtp_password }
        client = boto3.client("secretsmanager")
        responseData = {}
        try:
            response = client.create_secret(
                Name=f"{stack}/smtp/credentials",
                SecretString=json.dumps(secret)
            )        
            responseData = {"arn": response["ARN"]}
        except ClientError as e:
            if e.response["Error"]["Code"] == "ResourceExistsException":
                response = client.list_secrets(
                    Filters=[{"Key": "name", "Values": [f"{stack}/smtp/credentials"]}]
                )
                responseData = {"arn": response["SecretList"][0]["ARN"]}
            else:
                cfnresponse.send(event, context, cfnresponse.FAILED, {})
                traceback.print_exc()
                return
        cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData)
    except Exception:
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
        traceback.print_exc()
