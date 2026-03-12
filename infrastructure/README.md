# Infrastructure

Terraform configuration for deploying the Excel upload application to AWS.

## Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.0
- S3 bucket `comsheet-uploads` exists in us-west-2

## Deployment

```bash
cd infrastructure
terraform init
terraform plan
terraform apply
```

## Get API Endpoint

```bash
terraform output api_endpoint
```

Copy this URL and update it in `frontend/index.html`.

## Resources Created

- Lambda function with execution role
- API Gateway REST API with CORS
- CloudWatch Log Group
- IAM policies for S3 access

## Cleanup

```bash
terraform destroy
```
