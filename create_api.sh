#!/bin/bash

# Load environment variables from .env file
source .env

# Function to execute AWS CLI command and save output to a file
execute_aws_cli() {
  output_file=$1
  shift
  aws "$@" > "$output_file" || { record_progress "ABORT: Failed to execute AWS CLI command."; exit 1; }
}

# Function to record progress or error in the run-progress file
record_progress() {
  echo "$1" >> create_api.sh.run-progress.txt
}

# Initialize the installation artifacts JSON
installation_artifacts='{"iam_role":{},"lambda_function":{},"api_gateway":{},"integration":{},"route":{},"stage":{},"domain_name":{},"api_mapping":{},"route53_record":{}}'

echo "Creating IAM role for Lambda function..."
execute_aws_cli role.json iam create-role --role-name my-lambda-role --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' || exit 1
record_progress "CREATED_ROLE: IAM role created successfully."
installation_artifacts=$(jq '.iam_role = ('"$(cat role.json)"')' <<< "$installation_artifacts")

echo "Waiting for IAM role propagation..."
sleep 5

echo "Attaching AWSLambdaBasicExecutionRole policy to the IAM role..."
aws iam attach-role-policy --role-name my-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || { record_progress "ABORT: Failed to attach policy to IAM role."; exit 1; }
record_progress "ATTACHED_POLICY: Policy attached successfully."

echo "Waiting for policy attachment propagation..."
sleep 5

echo "Creating Lambda function..."
execute_aws_cli lambda.json lambda create-function --function-name my-lambda-function --runtime nodejs20.x --handler index.handler --role $(jq -r '.Role.Arn' role.json) --zip-file fileb://lambda_function.zip || exit 1
record_progress "CREATED_LAMBDA: Lambda function created successfully."
installation_artifacts=$(jq '.lambda_function = ('"$(cat lambda.json)"')' <<< "$installation_artifacts")

echo "Waiting for Lambda function creation propagation..."
sleep 5

echo "Creating HTTP API..."
execute_aws_cli api.json apigatewayv2 create-api --name my-http-api --protocol-type HTTP || exit 1
record_progress "CREATED_API: HTTP API created successfully."
installation_artifacts=$(jq '.api_gateway = ('"$(cat api.json)"')' <<< "$installation_artifacts")

# Get the API ID
api_id=$(jq -r '.ApiId' api.json)

echo "Creating integration..."
execute_aws_cli integration.json apigatewayv2 create-integration --api-id $api_id --integration-type AWS_PROXY --integration-uri arn:aws:apigateway:$REGION_NAME:lambda:path/2015-03-31/functions/$(jq -r '.FunctionArn' lambda.json)/invocations --payload-format-version 2.0 || exit 1
record_progress "CREATED_INTEGRATION: Integration created successfully."
installation_artifacts=$(jq '.integration = ('"$(cat integration.json)"')' <<< "$installation_artifacts")

# Get the integration ID
integration_id=$(jq -r '.IntegrationId' integration.json)

echo "Creating route..."
execute_aws_cli route.json apigatewayv2 create-route --api-id $api_id --route-key 'PUT /hello' --target integrations/$integration_id || exit 1
record_progress "CREATED_ROUTE: Route created successfully."
installation_artifacts=$(jq '.route = ('"$(cat route.json)"')' <<< "$installation_artifacts")

echo "Creating stage..."
execute_aws_cli stage.json apigatewayv2 create-stage --api-id $api_id --stage-name prod --auto-deploy || exit 1
record_progress "CREATED_STAGE: Stage created successfully."
installation_artifacts=$(jq '.stage = ('"$(cat stage.json)"')' <<< "$installation_artifacts")

echo "Waiting for stage creation propagation..."
sleep 5

echo "Creating domain name..."
execute_aws_cli domain_name.json apigatewayv2 create-domain-name --domain-name $domain_name --domain-name-configurations CertificateArn=$CERTIFICATE_ARN || exit 1
record_progress "CREATED_DOMAIN_NAME: Domain name created successfully."
installation_artifacts=$(jq '.domain_name = ('"$(cat domain_name.json)"')' <<< "$installation_artifacts")

echo "Waiting for domain name creation propagation..."
sleep 5

echo "Creating API mapping..."
execute_aws_cli api_mapping.json apigatewayv2 create-api-mapping --api-id $api_id --domain-name $domain_name --stage prod || exit 1
record_progress "CREATED_API_MAPPING: API mapping created successfully."
installation_artifacts=$(jq '.api_mapping = ('"$(cat api_mapping.json)"')' <<< "$installation_artifacts")

echo "API Gateway endpoint: https://$domain_name/hello"
record_progress "COMPLETED: API Gateway endpoint created successfully."

# Retrieve API domain name from api_mapping.json
api_domain_name=$(jq -r '.DomainName' api_mapping.json)

# Create Route53 record
hosted_zone_id=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${domain_name}. '].Id" --output text)
route53_record_json=$(aws route53 change-resource-record-sets --hosted-zone-id "$hosted_zone_id" --change-batch '{"Changes":[{"Action":"CREATE","ResourceRecordSet":{"Name":"pges2api.'${domain_name}'","Type":"CNAME","TTL":300,"ResourceRecords":[{"Value":"'${api_domain_name}'"}]}}]}' --query 'ChangeInfo.Id' --output json)
if [ -n "$route53_record_json" ]; then
  record_progress "CREATED_ROUTE53_RECORD: Route53 record created successfully."
  installation_artifacts=$(jq '.route53_record = '"$route53_record_json" <<< "$installation_artifacts")
else
  record_progress "ABORT: Failed to create Route53 record."
  exit 1
fi

# Save the installation artifacts to a file
echo "$installation_artifacts" > installation_artifacts.json
record_progress "SAVED_INSTALLATION_ARTIFACTS: Installation artifacts saved to installation_artifacts.json"