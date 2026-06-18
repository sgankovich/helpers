#!/bin/bash

# list_service_images.sh - List ECS service container images
#
# Usage:
#   ./list_service_images.sh [--cluster CLUSTER_NAME] [--region AWS_REGION]
#
#   --cluster: ECS cluster name (default: read from AWS_ECS_CLUSTER env var)
#   --region:  AWS region (default: read from AWS_REGION or AWS_DEFAULT_REGION env vars)
#
# Description:
#   Lists all ECS services in a cluster and displays each service name alongside
#   the container image tag for the first container definition in its task definition.
#
# Requirements:
#   - AWS CLI installed and configured with proper permissions
#   - jq (optional, for JSON parsing if needed)
#
# Environment Variables:
#   AWS_ECS_CLUSTER: Default cluster name if --cluster not specified
#   AWS_REGION:      Default AWS region if --region not specified
#   AWS_DEFAULT_REGION: Fallback region if AWS_REGION not set
#
# Example:
#   # Using command line arguments
#   ./list_service_images.sh --cluster my-cluster --region us-east-1
#
#   # Using environment variables
#   export AWS_ECS_CLUSTER="my-cluster"
#   export AWS_REGION="us-east-1"
#   ./list_service_images.sh
#
#   # List all services in a cluster
#   ./list_service_images.sh --cluster production-cluster --region eu-west-1

set -euo pipefail

# Parse command line arguments
CLUSTER=""
REGION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      CLUSTER="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--cluster CLUSTER_NAME] [--region AWS_REGION]"
      exit 1
      ;;
  esac
done

# Set defaults from environment variables
if [[ -z "$CLUSTER" ]]; then
  CLUSTER="${AWS_ECS_CLUSTER:-}"
fi

if [[ -z "$REGION" ]]; then
  REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
fi

# Validate required parameters
if [[ -z "$CLUSTER" ]]; then
  echo "Error: Cluster name is required."
  echo "  Provide via --cluster argument or AWS_ECS_CLUSTER environment variable."
  exit 1
fi

if [[ -z "$REGION" ]]; then
  echo "Error: AWS region is required."
  echo "  Provide via --region argument or AWS_REGION/AWS_DEFAULT_REGION environment variables."
  exit 1
fi

# Get list of all services in the cluster
SERVICES=$(aws ecs list-services \
  --cluster "$CLUSTER" \
  --region "$REGION" \
  --query "serviceArns[]" \
  --output text 2>/dev/null || true)

if [[ -z "$SERVICES" ]]; then
  echo "No services found in cluster: $CLUSTER"
  exit 0
fi

# Header
echo "ECS Services in cluster: $CLUSTER (region: $REGION)"
echo "--------------------------------------------------"

# Process each service
for SERVICE_ARN in $SERVICES; do
  # Extract service name from ARN
  SERVICE=$(basename "$SERVICE_ARN")

  # Get task definition for the service
  TASK_DEF=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION" \
    --query "services[0].taskDefinition" \
    --output text 2>/dev/null)

  if [[ "$TASK_DEF" == "None" || -z "$TASK_DEF" ]]; then
    echo "$SERVICE: no task definition found"
    continue
  fi

  # Get the image from the first container definition
  IMAGE=$(aws ecs describe-task-definition \
    --task-definition "$TASK_DEF" \
    --region "$REGION" \
    --query "taskDefinition.containerDefinitions[0].image" \
    --output text 2>/dev/null)

  if [[ -z "$IMAGE" ]]; then
    echo "$SERVICE: no image found"
    continue
  fi

  # Extract just the tag part (everything after the last colon)
  IMAGE_TAG="${IMAGE##*:}"

  printf "%-40s %s\n" "$SERVICE" "$IMAGE_TAG"
done

echo "--------------------------------------------------"
echo "Done."
