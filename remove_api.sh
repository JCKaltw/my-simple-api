#!/bin/bash

# Load environment variables from .env file
source .env

# Function to execute AWS CLI command and save output to a file
execute_aws_cli() {
  output_file=$1
  shift
  aws "$@" > "$output_file"
}

# Function to record progress in the run-progress file
record_progress() {
  echo "$1" >> remove_api.sh.run-progress.txt
}

if [ "$1" == "--force" ]; then
  echo "Force mode: Performing cleanup without progress file."

  # Delete API mapping
  api_mapping_id=$(aws apigatewayv2 get-api-mappings --domain-name $(jq -r '.DomainName' domain_name.json) --query 'Items[0].ApiMappingId' --output text 2>/dev/null || true)
  if [ -n "$api_mapping_id" ]; then
    echo "Deleting API mapping..."
    aws apigatewayv2 delete-api-mapping --api-mapping-id $api_mapping_id 2>/dev/null || true
    record_progress "DELETED_API_MAPPING: API mapping deleted successfully."
  fi

  # Delete domain name
  domain_name=$(jq -r '.DomainName' domain_name.json 2>/dev/null || true)
  if [ -n "$domain_name" ]; then
    echo "Deleting domain name..."
    aws apigatewayv2 delete-domain-name --domain-name $domain_name 2>/dev/null || true
    record_progress "DELETED_DOMAIN_NAME: Domain name deleted successfully."
  fi

  # Delete stage
  api_id=$(jq -r '.ApiId' api.json 2>/dev/null || true)
  if [ -n "$api_id" ]; then
    echo "Deleting stage..."
    aws apigatewayv2 delete-stage --api-id $api_id --stage-name prod 2>/dev/null || true
    record_progress "DELETED_STAGE: Stage deleted successfully."
  fi

  # Delete route
  if [ -n "$api_id" ]; then
    echo "Deleting route..."
    aws apigatewayv2 delete-route --api-id $api_id --route-key 'PUT /hello' 2>/dev/null || true
    record_progress "DELETED_ROUTE: Route deleted successfully."
  fi

  # Delete integration
  integration_id=$(jq -r '.IntegrationId' integration.json 2>/dev/null || true)
  if [ -n "$api_id" ] && [ -n "$integration_id" ]; then
    echo "Deleting integration..."
    aws apigatewayv2 delete-integration --api-id $api_id --integration-id $integration_id 2>/dev/null || true
    record_progress "DELETED_INTEGRATION: Integration deleted successfully."
  fi

  # Delete API
  if [ -n "$api_id" ]; then
    echo "Deleting HTTP API..."
    aws apigatewayv2 delete-api --api-id $api_id 2>/dev/null || true
    record_progress "DELETED_API: HTTP API deleted successfully."
  fi

  # Delete Lambda function
  echo "Deleting Lambda function..."
  aws lambda delete-function --function-name my-lambda-function 2>/dev/null || true
  record_progress "DELETED_LAMBDA: Lambda function deleted successfully."

  # Detach policy from IAM role
  echo "Detaching policy from IAM role..."
  aws iam detach-role-policy --role-name my-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
  record_progress "DETACHED_POLICY: Policy detached successfully."

  # Delete IAM role
  echo "Deleting IAM role..."
  aws iam delete-role --role-name my-lambda-role 2>/dev/null || true
  record_progress "DELETED_ROLE: IAM role deleted successfully."

  record_progress "CLEANUP_COMPLETED: Cleanup completed successfully."

  # Clean up temporary files
  rm -f role.json lambda.json api.json integration.json route.json stage.json domain_name.json api_mapping.json

  echo "Cleanup completed successfully."
else
  # Check if create_api.sh.run-progress.txt file exists
  if [ ! -f "create_api.sh.run-progress.txt" ]; then
    echo "Error: create_api.sh.run-progress.txt file not found."
    exit 1
  fi

  # Read the run-progress file in reverse order
  while read -r line; do
    # Extract the token and comment from the line
    token=$(echo "$line" | cut -d' ' -f1)
    comment=$(echo "$line" | cut -d' ' -f2-)

    case $token in
    "ABORT")
      echo "Skipping abort step: $comment"
      ;;
    "CREATED_API_MAPPING")
      echo "Deleting API mapping..."
      aws apigatewayv2 delete-api-mapping --api-mapping-id $(jq -r '.ApiMappingId' api_mapping.json) 2>/dev/null || true
      record_progress "DELETED_API_MAPPING: API mapping deleted successfully."
      ;;
    "CREATED_DOMAIN_NAME")
      echo "Deleting domain name..."
      aws apigatewayv2 delete-domain-name --domain-name $(jq -r '.DomainName' domain_name.json) 2>/dev/null || true
      record_progress "DELETED_DOMAIN_NAME: Domain name deleted successfully."
      ;;
    "CREATED_STAGE")
      echo "Deleting stage..."
      aws apigatewayv2 delete-stage --api-id $(jq -r '.ApiId' api.json) --stage-name prod 2>/dev/null || true
      record_progress "DELETED_STAGE: Stage deleted successfully."
      ;;
    "CREATED_ROUTE")
      echo "Deleting route..."
      aws apigatewayv2 delete-route --api-id $(jq -r '.ApiId' api.json) --route-key 'PUT /hello' 2>/dev/null || true
      record_progress "DELETED_ROUTE: Route deleted successfully."
      ;;
    "CREATED_INTEGRATION")
      echo "Deleting integration..."
      aws apigatewayv2 delete-integration --api-id $(jq -r '.ApiId' api.json) --integration-id $(jq -r '.IntegrationId' integration.json) 2>/dev/null || true
      record_progress "DELETED_INTEGRATION: Integration deleted successfully."
      ;;
    "CREATED_API")
      echo "Deleting HTTP API..."
      aws apigatewayv2 delete-api --api-id $(jq -r '.ApiId' api.json) 2>/dev/null || true
      record_progress "DELETED_API: HTTP API deleted successfully."
      ;;
    "CREATED_LAMBDA")
      echo "Deleting Lambda function..."
      aws lambda delete-function --function-name my-lambda-function 2>/dev/null || true
      record_progress "DELETED_LAMBDA: Lambda function deleted successfully."
      ;;
    "ATTACHED_POLICY")
      echo "Detaching policy from IAM role..."
      aws iam detach-role-policy --role-name my-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
      record_progress "DETACHED_POLICY: Policy detached successfully."
      ;;
    "CREATED_ROLE"|"REUSED_ROLE")
      echo "Deleting IAM role..."
      aws iam delete-role --role-name my-lambda-role 2>/dev/null || true
      record_progress "DELETED_ROLE: IAM role deleted successfully."
      ;;
    esac
  done < <(tail -r "create_api.sh.run-progress.txt")

  record_progress "CLEANUP_COMPLETED: Cleanup completed successfully."

  # Clean up temporary files
  rm -f role.json lambda.json api.json integration.json route.json stage.json domain_name.json api_mapping.json

  echo "Cleanup completed successfully."
fi