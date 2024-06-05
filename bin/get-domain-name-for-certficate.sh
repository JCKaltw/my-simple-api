#!/bin/bash

# Load environment variables from .env file
source .env

# Retrieve the domain names associated with the certificate
domain_names=$(aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN | jq -r '.Certificate.DomainName, .Certificate.SubjectAlternativeNames[]')

# Print the domain names
echo "Domain names associated with the certificate:"
echo "$domain_names"