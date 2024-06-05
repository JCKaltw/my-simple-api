#!/bin/bash

# Load environment variables from .env file
source .env

# Function to execute AWS CLI command and save output to a file
execute_aws_cli() {
  output_file=$1
  shift
  aws_command="aws $@"
  echo "Running: $aws_command"
  aws "$@" > "$output_file"
}

# Function to record progress or error in the run-progress file
record_progress() {
  echo "$1" >> create_api.sh.run-progress.txt
}

echo "Creating IAM role for Lambda function..."
execute_aws_cli role.json iam create-role --role-name my-lambda-role --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' || { record_progress "ABORT: Failed to create IAM role."; exit 1; }
record_progress "CREATED_ROLE: IAM role created successfully."

echo "Waiting for IAM role propagation..."
sleep 5

echo "Attaching AWSLambdaBasicExecutionRole policy to the IAM role..."
execute_aws_cli iam_policy_attachment.json iam attach-role-policy --role-name my-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || { record_progress "ABORT: Failed to attach policy to IAM role."; exit 1; }
record_progress "ATTACHED_POLICY: Policy attached successfully."

echo "Waiting for policy attachment propagation..."
sleep 5

echo "Creating Lambda function..."
execute_aws_cli lambda.json lambda create-function --function-name my-lambda-function --runtime nodejs20.x --handler index.handler --role $(jq -r '.Role.Arn' role.json) --zip-file fileb://lambda_function.zip || { record_progress "ABORT: Failed to create Lambda function."; exit 1; }
record_progress "CREATED_LAMBDA: Lambda function created successfully."

echo "Waiting for Lambda function creation propagation..."
sleep 5

echo "Creating HTTP API..."
execute_aws_cli api.json apigatewayv2 create-api --name my-http-api --protocol-type HTTP || { record_progress "ABORT: Failed to create HTTP API."; exit 1; }
record_progress "CREATED_API: HTTP API created successfully."

# Get the API ID
api_id=$(jq -r '.ApiId' api.json)

echo "Creating integration..."
execute_aws_cli integration.json apigatewayv2 create-integration --api-id $api_id --integration-type AWS_PROXY --integration-uri arn:aws:apigateway:$REGION_NAME:lambda:path/2015-03-31/functions/$(jq -r '.FunctionArn' lambda.json)/invocations --payload-format-version 2.0 || { record_progress "ABORT: Failed to create integration."; exit 1; }
record_progress "CREATED_INTEGRATION: Integration created successfully."

# Get the integration ID
integration_id=$(jq -r '.IntegrationId' integration.json)

echo "Creating route..."
execute_aws_cli route.json apigatewayv2 create-route --api-id $api_id --route-key 'PUT /hello' --target integrations/$integration_id || { record_progress "ABORT: Failed to create route."; exit 1; }
record_progress "CREATED_ROUTE: Route created successfully."

echo "Creating stage..."
execute_aws_cli stage.json apigatewayv2 create-stage --api-id $api_id --stage-name prod --auto-deploy || { record_progress "ABORT: Failed to create stage."; exit 1; }
record_progress "CREATED_STAGE: Stage created successfully."

echo "Waiting for stage creation propagation..."
sleep 5

echo "Retrieving domain name from certificate..."
domain_name=$(aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN | jq -r '.Certificate.DomainName')

if [ -z "$domain_name" ]; then
  echo "Failed to retrieve domain name from certificate."
  record_progress "ABORT: Failed to retrieve domain name from certificate."
  exit 1
fi

echo "Domain name: $domain_name"

echo "Creating domain name..."
execute_aws_cli domain_name.json apigatewayv2 create-domain-name --domain-name $domain_name --domain-name-configurations CertificateArn=$CERTIFICATE_ARN || { record_progress "ABORT: Failed to create domain name."; exit 1; }
record_progress "CREATED_DOMAIN_NAME: Domain name created successfully."

echo "Waiting for domain name creation propagation..."
sleep 5

echo "Creating API mapping..."
execute_aws_cli api_mapping.json apigatewayv2 create-api-mapping --api-id $api_id --domain-name $domain_name --stage prod || { record_progress "ABORT: Failed to create API mapping."; exit 1; }
record_progress "CREATED_API_MAPPING: API mapping created successfully."

echo "API Gateway endpoint: https://$domain_name/hello"
record_progress "COMPLETED: API Gateway endpoint created successfully."

# Retrieve API domain name from api_mapping.json
api_domain_name=$(jq -r '.DomainName' api_mapping.json)

# Create Route53 record
hosted_zone_id=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${domain_name}. '].Id" --output text)
echo '{"Changes":[{"Action":"CREATE","ResourceRecordSet":{"Name":"pges2api.'${domain_name}'","Type":"CNAME","TTL":300,"ResourceRecords":[{"Value":"'${api_domain_name}'"}]}}]}' > change_batch.json
execute_aws_cli route53_record.json route53 change-resource-record-sets --hosted-zone-id "$hosted_zone_id" --change-batch file://change_batch.json || { record_progress "ABORT: Failed to create Route53 record."; exit 1; }
record_progress "CREATED_ROUTE53_RECORD: Route53 record created successfully."