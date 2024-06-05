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
hosted_zone_id=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${domain_name}. '].Id" --output text)
record_name="pges2api.${domain_name}"
record_value=$(aws apigatewayv2 get-api-mapping --domain-name "$domain_name" --query 'ApiMappings[?Tags[?Key==`Project` && Value==`my-simple-api`]].DomainName' --output text)
if [ -n "$record_value" ]; then
  echo "Removing Route53 record..."
  execute_aws_cli route53 change-resource-record-sets --hosted-zone-id "$hosted_zone_id" --change-batch "{\"Changes\":[{\"Action\":\"DELETE\",\"ResourceRecordSet\":{\"Name\":\"$record_name\",\"Type\":\"CNAME\",\"TTL\":300,\"ResourceRecords\":[{\"Value\":\"$record_value\"}]}}]}"
  record_progress "REMOVED_ROUTE53_RECORD: Route53 record removed successfully."
else
  echo "Skipping Route53 record removal as the record does not exist."
fi

# Remove API mapping
api_mapping_id=$(aws apigatewayv2 get-api-mappings --query 'Items[?Tags[?Key==`Project` && Value==`my-simple-api`]].ApiMappingId' --output text)
if [ -n "$api_mapping_id" ]; then
  echo "Removing API mapping..."
  execute_aws_cli apigatewayv2 delete-api-mapping --api-mapping-id "$api_mapping_id" --domain-name "$domain_name"
  record_progress "REMOVED_API_MAPPING: API mapping removed successfully."
else
  echo "Skipping API mapping removal as the mapping does not exist."
fi

# Remove domain name
domain_name_id=$(aws apigatewayv2 get-domain-names --query 'Items[?Tags[?Key==`Project` && Value==`my-simple-api`]].DomainNameId' --output text)
if [ -n "$domain_name_id" ]; then
  echo "Removing domain name..."
  execute_aws_cli apigatewayv2 delete-domain-name --domain-name "$domain_name"
  record_progress "REMOVED_DOMAIN_NAME: Domain name removed successfully."
else
  echo "Skipping domain name removal as the domain name does not exist."
fi

# Remove stage
api_id=$(aws apigatewayv2 get-apis --query 'Items[?Tags[?Key==`Project` && Value==`my-simple-api`]].ApiId' --output text)
stage_name=$(aws apigatewayv2 get-stages --api-id "$api_id" --query 'Items[?Tags[?Key==`Project` && Value==`my-simple-api`]].StageName' --output text)
if [ -n "$stage_name" ]; then
  echo "Removing stage..."
  execute_aws_cli apigatewayv2 delete-stage --api-id "$api_id" --stage-name "$stage_name"
  record_progress "REMOVED_STAGE: Stage removed successfully."
else
  echo "Skipping stage removal as the stage does not exist."
fi

# Remove route
route_id=$(aws apigatewayv2 get-routes --api-id "$api_id" --query 'Items[0].RouteId' --output text)
if [ -n "$route_id" ]; then
  echo "Removing route..."
  execute_aws_cli apigatewayv2 delete-route --api-id "$api_id" --route-id "$route_id"
  record_progress "REMOVED_ROUTE: Route removed successfully."
else
  echo "Skipping route removal as the route does not exist."
fi

# Remove integration
integration_id=$(aws apigatewayv2 get-integrations --api-id "$api_id" --query 'Items[0].IntegrationId' --output text)
if [ -n "$integration_id" ]; then
  echo "Removing integration..."
  execute_aws_cli apigatewayv2 delete-integration --api-id "$api_id" --integration-id "$integration_id"
  record_progress "REMOVED_INTEGRATION: Integration removed successfully."
else
  echo "Skipping integration removal as the integration does not exist."
fi

# Remove API
if [ -n "$api_id" ]; then
  echo "Removing API..."
  execute_aws_cli apigatewayv2 delete-api --api-id "$api_id"
  record_progress "REMOVED_API: API removed successfully."
else
  echo "Skipping API removal as the API does not exist."
fi

# Remove Lambda function
function_name=$(aws lambda list-functions --query 'Functions[?Tags[?Key==`Project` && Value==`my-simple-api`]].FunctionName' --output text)
if [ -n "$function_name" ]; then
  echo "Removing Lambda function..."
  execute_aws_cli lambda delete-function --function-name "$function_name"
  record_progress "REMOVED_LAMBDA: Lambda function removed successfully."
else
  echo "Skipping Lambda function removal as the function does not exist."
fi

# Remove IAM policy attachment
aws iam detach-role-policy --role-name my-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || { echo "WARNING: Failed to detach IAM policy."; }
record_progress "REMOVED_IAM_POLICY_ATTACHMENT: IAM policy attachment removed successfully."

# Remove IAM role
role_name=$(aws iam list-roles --query 'Roles[?Tags[?Key==`Project` && Value==`my-simple-api`]].RoleName' --output text)
if [ -n "$role_name" ]; then
  echo "Removing IAM role..."
  execute_aws_cli iam delete-role --role-name "$role_name"
  record_progress "REMOVED_IAM_ROLE: IAM role removed successfully."
else
  echo "Skipping IAM role removal as the role does not exist."
fi

record_progress "COMPLETED: API Gateway resources removed successfully."