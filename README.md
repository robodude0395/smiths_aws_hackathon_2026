# Excel Upload to S3 Application

A simple web application for uploading Excel files to S3 with metadata tagging.

## Architecture

- **Frontend**: Single-page HTML/JavaScript application with drag-and-drop upload
- **Backend**: Python Lambda function that generates pre-signed S3 POST URLs
- **Storage**: Files uploaded directly to S3 bucket `comsheet-uploads`

## Features

- ✅ Drag-and-drop or file picker for Excel files (.xlsx, .xls)
- ✅ Client and server-side validation (file type, size < 50MB)
- ✅ Direct upload to S3 using pre-signed URLs (bypasses API Gateway limits)
- ✅ S3 object tagging with metadata (programme_name, uploaded_by, upload_timestamp, status)
- ✅ Real-time upload progress and status feedback
- ✅ CORS-enabled for public access

## Project Structure

```
.
├── frontend/               # Frontend application
│   ├── index.html         # Single-page upload UI
│   └── README.md          # Frontend documentation
├── backend/               # Lambda function
│   ├── lambda_function.py # Python handler
│   ├── requirements.txt   # Python dependencies
│   └── README.md          # Backend documentation
├── infrastructure/        # Terraform IaC
│   ├── main.tf           # AWS resources
│   └── README.md         # Deployment guide
└── README.md             # This file
```

## Quick Start

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform installed (>= 1.0)
- S3 bucket `comsheet-uploads` already exists in us-west-2

### Deployment Steps

1. **Deploy infrastructure:**

```bash
cd infrastructure
terraform init
terraform apply
```

2. **Get the API endpoint:**

```bash
terraform output api_endpoint
```

3. **Update the frontend:**

Copy and configure the API endpoint:

```bash
cd frontend
cp config.example.js config.js
```

Edit `config.js` and replace with the API endpoint from step 2:

```javascript
const CONFIG = {
    API_ENDPOINT: 'https://xxxxxxxxxx.execute-api.us-west-2.amazonaws.com/prod/upload'
};
```

4. **Test the application:**

Open `frontend/index.html` in a browser or serve it locally:

```bash
cd frontend
python3 -m http.server 8000
# Visit http://localhost:8000
```

## S3 Upload Path Structure

Files are uploaded to:
```
s3://comsheet-uploads/{programme_name}/{timestamp}_{original_filename}
```

Example:
```
s3://comsheet-uploads/MyProgramme/20240312_143022_data.xlsx
```

## S3 Object Tags

Each uploaded file is tagged with:
- `programme_name`: User-provided programme name
- `uploaded_by`: User-provided uploader name
- `upload_timestamp`: ISO 8601 timestamp
- `status`: Set to "pending_transform"

## IAM Permissions

The Lambda function has permissions to:
- `s3:PutObject` on `comsheet-uploads/*`
- `s3:PutObjectTagging` on `comsheet-uploads/*`
- CloudWatch Logs for monitoring

## Cleanup

To destroy all resources:

```bash
cd infrastructure
terraform destroy
```

Note: This will NOT delete the S3 bucket or its contents.

## Troubleshooting

- **CORS errors**: Ensure the API endpoint is correctly set in `frontend/index.html`
- **Upload fails**: Check Lambda logs in CloudWatch (`/aws/lambda/excel-upload-handler`)
- **403 errors**: Verify Lambda IAM role has S3 permissions
- **Bucket not found**: Ensure `comsheet-uploads` bucket exists in us-west-2
