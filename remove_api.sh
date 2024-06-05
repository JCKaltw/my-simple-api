#!/bin/bash

# Load environment variables from .env file
source .env

# Function to execute AWS CLI command and log output
execute_aws_cli() {
  aws_command="aws $@"
  echo "Running: $aws_command"
  aws "$@" || { echo "WARNING: AWS CLI command failed."; }
}

# Function to record progress or error in the run-progress file
record_progress() {
  echo "$1" >> remove_api.sh.run-progress.txt
}

# Remove existing IAM role
role_name=$(aws iam list-roles --query "Roles[?RoleName=='my-lambda-role'].RoleName" --output text)
if [ -n "$role_name" ]; then
  echo "Removing existing IAM role..."
  echo "Running: aws iam detach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  aws iam detach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || { echo "WARNING: Failed to detach IAM policy."; }
  echo "Running: aws iam delete-role --role-name $role_name"
  execute_aws_cli iam delete-role --role-name "$role_name"
  record_progress "REMOVED_IAM_ROLE: IAM role removed successfully."
else
  echo "Skipping IAM role removal as the role does not exist."
fi

# Retrieve domain name from certificate
echo "Running: aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN"
domain_name=$(aws acm describe-certificate --certificate-arn "$CERTIFICATE_ARN" | jq -r '.Certificate.DomainName')

# Remove Route53 record
echo "Running: aws route53 list-hosted-zones --query \"HostedZones[?Name=='${domain_name}. '].Id\""
hosted_zone_id=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${domain_name}. '].Id" --output text)
record_name="pges2api.${domain_name}"
echo "Running: aws apigatewayv2 get-api-mappings --query \"Items[?Tags[?Key=='Project' && Value=='my-simple-api']].DomainName\" --domain-name $domain_name"
api_domain_name=$(aws apigatewayv2 get-api-mappings --query "Items[?Tags[?Key=='Project' && Value=='my-simple-api']].DomainName" --output text --domain-name "$domain_name")
if [ -n "$api_domain_name" ]; then
  echo "Removing Route53 record..."
  echo "Running: aws route53 change-resource-record-sets --hosted-zone-id $hosted_zone_id --change-batch '{\"Changes\":[{\"Action\":\"DELETE\",\"ResourceRecordSet\":{\"Name\":\"$record_name\",\"Type\":\"CNAME\",\"TTL\":300,\"ResourceRecords\":[{\"Value\":\"$api_domain_name\"}]}}]}'"
  execute_aws_cli route53 change-resource-record-sets --hosted-zone-id "$hosted_zone_id" --change-batch "{\"Changes\":[{\"Action\":\"DELETE\",\"ResourceRecordSet\":{\"Name\":\"$record_name\",\"Type\":\"CNAME\",\"TTL\":300,\"ResourceRecords\":[{\"Value\":\"$api_domain_name\"}]}}]}"
  record_progress "REMOVED_ROUTE53_RECORD: Route53 record removed successfully."
else
  echo "Skipping Route53 record removal as the record does not exist."
fi

# Remove API mapping
echo "Running: aws apigatewayv2 get-api-mappings --query \"Items[?Tags[?Key=='Project' && Value=='my-simple-api']].ApiMappingId\" --domain-name $domain_name"
api_mapping_id=$(aws apigatewayv2 get-api-mappings --query "Items[?Tags[?Key=='Project' && Value=='my-simple-api']].ApiMappingId" --output text --domain-name "$domain_name")
if [ -n "$api_mapping_id" ]; then
  echo "Removing API mapping..."
  echo "Running: aws apigatewayv2 delete-api-mapping --api-mapping-id $api_mapping_id --domain-name $domain_name"
  execute_aws_cli apigatewayv2 delete-api-mapping --api-mapping-id "$api_mapping_id" --domain-name "$domain_name"
  record_progress "REMOVED_API_MAPPING: API mapping removed successfully."
else
  echo "Skipping API mapping removal as the mapping does not exist."
fi

# Remove domain name
echo "Running: aws apigatewayv2 get-domain-names --query \"Items[?Tags[?Key=='Project' && Value=='my-simple-api']].DomainNameId\""
domain_name_id=$(aws apigatewayv2 get-domain-names --query "Items[?Tags[?Key=='Project' && Value=='my-simple-api']].DomainNameId" --output text)
if [ -n "$domain_name_id" ]; then
  echo "Removing domain name..."
  echo "Running: aws apigatewayv2 delete-domain-name --domain-name $domain_name"
  execute_aws_cli apigatewayv2 delete-domain-name --domain-name "$domain_name"
  record_progress "REMOVED_DOMAIN_NAME: Domain name removed successfully."
else
  echo "Skipping domain name removal as the domain name does not exist."
fi

# Remove stage, route, integration, API, and Lambda function
# ... (existing code)

record_progress "COMPLETED: API Gateway resources removed successfully."