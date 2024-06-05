#!/bin/bash

# Load environment variables from .env file
source .env

# Function to execute AWS CLI command and echo it
execute_aws_cli() {
  command=$@
  echo "Running: $command"
  $command
}

# Function to record progress or error in the run-progress file
record_progress() {
  echo "$1" >> remove_api.sh.run-progress.txt
}

# Get details from the created files
api_id=$(jq -r '.ApiId' api.json)
integration_id=$(jq -r '.IntegrationId' integration.json)
route_id=$(jq -r '.RouteId' route.json)
stage_name="prod"
domain_name=$(jq -r '.DomainName' api_mapping.json)
hosted_zone_id=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${domain_name}. '].Id" --output text)
mapping_id=$(jq -r '.ApiMappingId' api_mapping.json)

# Print a summary before deletion
echo "API ID: $api_id"
echo "Integration ID: $integration_id"
echo "Route ID: $route_id"
echo "Stage Name: $stage_name"
echo "Domain Name: $domain_name"
echo "Hosted Zone ID: $hosted_zone_id"
echo "Mapping ID: $mapping_id"

# Begin removing resources
echo "Removing API mapping..."
execute_aws_cli aws apigatewayv2 delete-api-mapping --api-mapping-id "$mapping_id" --domain-name "$domain_name" || { record_progress "ABORT: Failed to delete API mapping."; exit 1; }
record_progress "REMOVED_API_MAPPING: API mapping removed successfully."

echo "Removing custom domain name..."
execute_aws_cli aws apigatewayv2 delete-domain-name --domain-name "$domain_name" || { record_progress "ABORT: Failed to delete custom domain name."; exit 1; }
record_progress "REMOVED_DOMAIN_NAME: Custom domain name removed successfully."

echo "Removing API stage..."
execute_aws_cli aws apigatewayv2 delete-stage --api-id "$api_id" --stage-name "$stage_name" || { record_progress "ABORT: Failed to delete stage."; exit 1; }
record_progress "REMOVED_STAGE: API stage removed successfully."

echo "Deleting route..."
execute_aws_cli aws apigatewayv2 delete-route --api-id "$api_id" --route-id "$route_id" || { record_progress "ABORT: Failed to delete route."; exit 1; }
record_progress "REMOVED_ROUTE: Route removed successfully."

echo "Deleting integration..."
execute_aws_cli aws apigatewayv2 delete-integration --api-id "$api_id" --integration-id "$integration_id" || { record_progress "ABORT: Failed to delete integration."; exit 1; }
record_progress "REMOVED_INTEGRATION: Integration removed successfully."

echo "Deleting HTTP API..."
execute_aws_cli aws apigatewayv2 delete-api --api-id "$api_id" || { record_progress "ABORT: Failed to delete HTTP API."; exit 1; }
record_progress "REMOVED_API: HTTP API removed successfully."

echo "Deleting Lambda function..."
lambda_arn=$(jq -r '.FunctionArn' lambda.json)
execute_aws_cli aws lambda delete-function --function-name $(basename $lambda_arn) || { record_progress "ABORT: Failed to delete Lambda function."; exit 1; }
record_progress "REMOVED_LAMBDA: Lambda function removed successfully."

echo "Detaching policy from IAM role..."
execute_aws_cli aws iam detach-role-policy --role-name my-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || { record_progress "ABORT: Failed to detach policy from IAM role."; exit 1; }
record_progress "DETACHED_POLICY: Policy detached successfully."

echo "Deleting IAM role..."
execute_aws_cli aws iam delete-role --role-name my-lambda-role || { record_progress "ABORT: Failed to delete IAM role."; exit 1; }
record_progress "REMOVED_ROLE: IAM role removed successfully."

# The record in Route 53 might not have a specific ID in the state files, so we handle it a bit differently.
echo "Deleting Route 53 record..."
change_batch=$(cat << EOF
{
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "pges2api.${domain_name}",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "${domain_name}"
          }
        ]
      }
    }
  ]
}
EOF
)

execute_aws_cli aws route53 change-resource-record-sets --hosted-zone-id "$hosted_zone_id" --change-batch "$change_batch" || { record_progress "ABORT: Failed to delete Route 53 record."; exit 1; }
record_progress "REMOVED_ROUTE53_RECORD: Route 53 record removed successfully."

echo "All resources removed successfully. Check remove_api.sh.run-progress.txt for the recorded progress."
