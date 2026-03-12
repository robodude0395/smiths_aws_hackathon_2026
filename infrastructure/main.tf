terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# Create S3 bucket for uploads
resource "aws_s3_bucket" "uploads" {
  bucket = "comsheet-uploads"

  tags = {
    Name        = "Excel Uploads"
    Environment = "Production"
  }
}

# Enable versioning for the bucket
resource "aws_s3_bucket_versioning" "uploads_versioning" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Block public access to the bucket
resource "aws_s3_bucket_public_access_block" "uploads_public_access" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name = "excel-upload-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM policy for Lambda to access S3
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda-s3-access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectTagging",
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.uploads.arn}/*",
          "${aws_s3_bucket.uploads.arn}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Package upload Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../backend/lambda_function.py"
  output_path = "lambda_function.zip"
}

# Package list files Lambda function
data "archive_file" "list_lambda_zip" {
  type        = "zip"
  source_file = "../backend/list_files_function.py"
  output_path = "list_files_function.zip"
}

# Lambda function
resource "aws_lambda_function" "upload_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "excel-upload-handler"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = 30

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.uploads.id
    }
  }
}

# Lambda function for listing files
resource "aws_lambda_function" "list_files_handler" {
  filename         = data.archive_file.list_lambda_zip.output_path
  function_name    = "excel-list-files-handler"
  role            = aws_iam_role.lambda_role.arn
  handler         = "list_files_function.lambda_handler"
  source_code_hash = data.archive_file.list_lambda_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = 30

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.uploads.id
    }
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.upload_handler.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "list_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.list_files_handler.function_name}"
  retention_in_days = 7
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "upload_api" {
  name        = "excel-upload-api"
  description = "API for Excel file upload to S3"
}

# API Gateway Resources
resource "aws_api_gateway_resource" "upload_resource" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  parent_id   = aws_api_gateway_rest_api.upload_api.root_resource_id
  path_part   = "upload"
}

resource "aws_api_gateway_resource" "files_resource" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  parent_id   = aws_api_gateway_rest_api.upload_api.root_resource_id
  path_part   = "files"
}

# API Gateway Method - POST
resource "aws_api_gateway_method" "upload_post" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_resource.upload_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Method - OPTIONS (for CORS)
resource "aws_api_gateway_method" "upload_options" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_resource.upload_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# API Gateway Integration - POST
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.upload_api.id
  resource_id             = aws_api_gateway_resource.upload_resource.id
  http_method             = aws_api_gateway_method.upload_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.upload_handler.invoke_arn
}

# API Gateway Integration - OPTIONS (for CORS)
resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.upload_resource.id
  http_method = aws_api_gateway_method.upload_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# API Gateway Method Response - OPTIONS
resource "aws_api_gateway_method_response" "options_response" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.upload_resource.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# API Gateway Integration Response - OPTIONS
resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.upload_resource.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = aws_api_gateway_method_response.options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.upload_api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "upload_deployment" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id

  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration.options_integration,
    aws_api_gateway_integration.list_lambda_integration,
    aws_api_gateway_integration.files_options_integration
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "upload_stage" {
  deployment_id = aws_api_gateway_deployment.upload_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  stage_name    = "prod"
}

# Outputs
output "api_endpoint" {
  description = "API Gateway endpoint URL - use this in index.html"
  value       = "${aws_api_gateway_stage.upload_stage.invoke_url}/upload"
}

output "files_api_endpoint" {
  description = "API Gateway endpoint for listing files"
  value       = "${aws_api_gateway_stage.upload_stage.invoke_url}/files"
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.upload_handler.function_name
}

output "s3_bucket" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.uploads.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.uploads.arn
}

# API Gateway Method - GET /files
resource "aws_api_gateway_method" "files_get" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_resource.files_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway Method - OPTIONS /files (for CORS)
resource "aws_api_gateway_method" "files_options" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_resource.files_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# API Gateway Integration - GET /files
resource "aws_api_gateway_integration" "list_lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.upload_api.id
  resource_id             = aws_api_gateway_resource.files_resource.id
  http_method             = aws_api_gateway_method.files_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.list_files_handler.invoke_arn
}

# API Gateway Integration - OPTIONS /files (for CORS)
resource "aws_api_gateway_integration" "files_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.files_resource.id
  http_method = aws_api_gateway_method.files_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# API Gateway Method Response - OPTIONS /files
resource "aws_api_gateway_method_response" "files_options_response" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.files_resource.id
  http_method = aws_api_gateway_method.files_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# API Gateway Integration Response - OPTIONS /files
resource "aws_api_gateway_integration_response" "files_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.files_resource.id
  http_method = aws_api_gateway_method.files_options.http_method
  status_code = aws_api_gateway_method_response.files_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Lambda permission for API Gateway - list files
resource "aws_lambda_permission" "list_api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_files_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.upload_api.execution_arn}/*/*"
}
