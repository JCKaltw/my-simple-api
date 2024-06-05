#!/bin/bash

# Load environment variables from .env file
source .env

# Function to execute AWS CLI command and log output
execute_aws_cli() {
  aws_command="aws $@"
  echo "Running: $aws_command"
  if $force_removal; then
    aws "$@" || { echo "WARNING: AWS CLI command failed."; }
  else
    aws "$@" || { echo "ABORT: AWS CLI command failed."; exit 1; }
  fi
}

# Function to record progress or error in the run-progress file
record_progress() {
  echo "$1" >> remove_api.sh.run-progress.txt
}

# Check if the --force flag is set
force_removal=false
if [ "$1" == "--force" ]; then
  force_removal=true
fi

# Retrieve domain name from certificate
domain_name=$(aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN | jq -r '.Certificate.DomainName')

# Remove Route53 record
if [ -f "route53_record.json" ]; then
  hosted_zone_id=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${domain_name}. '].Id" --output text)
  change_id=$(jq -r '.ChangeInfo.Id' route53_record.json)
  echo "Input file: route53_record.json"
  echo "Removing Route53 record..."
  execute_aws_cli route53 change-resource-record-sets --hosted-zone-id "$hosted_zone_id" --change-batch "{\"Changes\":[{\"Action\":\"DELETE\",\"ResourceRecordSet\":{\"Name\":\"pges2api.${domain_name}.\",\"Type\":\"CNAME\",\"TTL\":300,\"ResourceRecords\":[{\"Value\":\"$(jq -r '.DomainName' api_mapping.json)\"}]}}]}"
  record_progress "REMOVED_ROUTE53_RECORD: Route53 record removed successfully."
else
  echo "Skipping Route53 record removal as route53_record.json does not exist."
fi

# Remove API mapping
if [ -f "api_mapping.json" ]; then
  api_id=$(jq -r '.ApiId' api.json)
  domain_name=$(jq -r '.DomainName' api_mapping.json)
  echo "Input file: api_mapping.json"
  echo "Removing API mapping..."
  execute_aws_cli apigatewayv2 delete-api-mapping --api-mapping-id $(jq -r '.ApiMappingId' api_mapping.json) --domain-name $domain_name
  record_progress "REMOVED_API_MAPPING: API mapping removed successfully."
else
  echo "Skipping API mapping removal as api_mapping.json does not exist."
fi

# Remove domain name
if [ -f "domain_name.json" ]; then
  echo "Input file: domain_name.json"
  echo "Removing domain name..."
  execute_aws_cli apigatewayv2 delete-domain-name --domain-name $(jq -r '.DomainName' domain_name.json)
  record_progress "REMOVED_DOMAIN_NAME: Domain name removed successfully."
else
  echo "Skipping domain name removal as domain_name.json does not exist."
fi

# Remove stage
if [ -f "stage.json" ]; then
  api_id=$(jq -r '.ApiId' api.json)
  echo "Input file: stage.json"
  echo "Removing stage..."
  execute_aws_cli apigatewayv2 delete-stage --api-id $api_id --stage-name $(jq -r '.StageName' stage.json)
  record_progress "REMOVED_STAGE: Stage removed successfully."
else
  echo "Skipping stage removal as stage.json does not exist."
fi

# Remove route
if [ -f "route.json" ]; then
  api_id=$(jq -r '.ApiId' api.json)
  echo "Input file: route.json"
  echo "Removing route..."
  execute_aws_cli apigatewayv2 delete-route --api-id $api_id --route-id $(jq -r '.RouteId' route.json)
  record_progress "REMOVED_ROUTE: Route removed successfully."
else
  echo "Skipping route removal as route.json does not exist."
fi

# Remove integration
if [ -f "integration.json" ]; then
  api_id=$(jq -r '.ApiId' api.json)
  echo "Input file: integration.json"
  echo "Removing integration..."
  execute_aws_cli apigatewayv2 delete-integration --api-id $api_id --integration-id $(jq -r '.IntegrationId' integration.json)
  record_progress "REMOVED_INTEGRATION: Integration removed successfully."
else
  echo "Skipping integration removal as integration.json does not exist."
fi

# Remove API
if [ -f "api.json" ]; then
  api_id=$(jq -r '.ApiId' api.json)
  echo "Input file: api.json"
  echo "Removing API..."
  execute_aws_cli apigatewayv2 delete-api --api-id $api_id
  record_progress "REMOVED_API: API removed successfully."
else
  echo "Skipping API removal as api.json does not exist."
fi

# Remove Lambda function
if [ -f "lambda.json" ]; then
  echo "Input file: lambda.json"
  echo "Removing Lambda function..."
  execute_aws_cli lambda delete-function --function-name $(jq -r '.Configuration.FunctionName' lambda.json)
  record_progress "REMOVED_LAMBDA: Lambda function removed successfully."
else
  echo "Skipping Lambda function removal as lambda.json does not exist."
fi

# Remove IAM policy attachment
if [ -f "iam_policy_attachment.json" ]; then
  echo "Input file: iam_policy_attachment.json"
  echo "Removing IAM policy attachment..."
  aws iam detach-role-policy --role-name my-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  record_progress "REMOVED_IAM_POLICY_ATTACHMENT: IAM policy attachment removed successfully."
else
  echo "Skipping IAM policy attachment removal as iam_policy_attachment.json does not exist."
fi

# Remove IAM role
if [ -f "role.json" ]; then
  echo "Input file: role.json"
  echo "Removing IAM role..."
  execute_aws_cli iam delete-role --role-name $(jq -r '.Role.RoleName' role.json)
  record_progress "REMOVED_IAM_ROLE: IAM role removed successfully."
else
  echo "Skipping IAM role removal as role.json does not exist."
fi

record_progress "COMPLETED: API Gateway resources removed successfully."