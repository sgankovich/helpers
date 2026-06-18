# ECS List Service Images

A Bash script to list all ECS services in a cluster and display their container image tags.

## Overview

This script queries AWS ECS to retrieve all services in a specified cluster, then extracts and displays the container image tag for each service's first container definition in its task definition.

## Usage

### Command Line Arguments

```bash
./list_service_images.sh [--cluster CLUSTER_NAME] [--region AWS_REGION]
```

**Options:**
- `--cluster`: ECS cluster name (required if `AWS_ECS_CLUSTER` env var not set)
- `--region`: AWS region (required if `AWS_REGION` or `AWS_DEFAULT_REGION` env vars not set)

### Environment Variables

The script can also be configured entirely via environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_ECS_CLUSTER` | ECS cluster name | None (required) |
| `AWS_REGION` | AWS region | None (required) |
| `AWS_DEFAULT_REGION` | Fallback AWS region | None |

### Examples

```bash
# Using command line arguments
./list_service_images.sh --cluster my-cluster --region us-east-1

# Using environment variables
export AWS_ECS_CLUSTER="my-cluster"
export AWS_REGION="us-east-1"
./list_service_images.sh

# Mixed approach (cluster from env, region from argument)
export AWS_ECS_CLUSTER="production-cluster"
./list_service_images.sh --region eu-west-1
```

## Output

The script produces a formatted table showing:
- Service name (left-aligned, 40 characters wide)
- Image tag (extracted from the image URI)

Example output:
```
ECS Services in cluster: my-cluster (region: us-east-1)
--------------------------------------------------
my-service-1                            v1.2.3
my-service-2                            latest
my-service-3                            sha-abc1234
--------------------------------------------------
Done.
```

## Requirements

- **AWS CLI**: Must be installed and configured with proper IAM permissions
- **Permissions**: The IAM user/role must have permissions for:
  - `ecs:ListServices`
  - `ecs:DescribeServices`
  - `ecs:DescribeTaskDefinition`

## How It Works

1. Lists all ECS services in the specified cluster
2. For each service:
   - Retrieves the task definition ARN
   - Describes the task definition to get container definitions
   - Extracts the image URI from the first container definition
   - Parses the image tag (everything after the last `:` in the image URI)
3. Displays the results in a formatted table

## Notes

- The script only shows the **first container** in each task definition. If your task definitions have multiple containers and you need to see all of them, you would need to modify the script.
- The image tag is extracted by taking everything after the last colon (`:`) in the image URI. This works for standard Docker image formats like `repository:tag` or `repository@sha256:digest`.
- Services without a task definition or without container definitions will be noted in the output.
- The script uses `set -euo pipefail` for safer error handling.

## Error Handling

The script validates that:
- A cluster name is provided (via argument or environment variable)
- A region is provided (via argument or environment variable)
- AWS CLI commands succeed (errors will cause the script to exit)

If no services are found in the cluster, the script will exit with a message and return code 0.

## Making the Script Executable

```bash
chmod +x list_service_images.sh
```

## Related AWS CLI Commands

For reference, here are the underlying AWS CLI commands used:

```bash
# List all services in a cluster
aws ecs list-services --cluster CLUSTER_NAME --region REGION

# Describe a specific service
aws ecs describe-services --cluster CLUSTER_NAME --services SERVICE_NAME --region REGION

# Describe a task definition
aws ecs describe-task-definition --task-definition TASK_DEF_ARN --region REGION
```
