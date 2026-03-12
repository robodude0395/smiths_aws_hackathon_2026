# Backend

Python Lambda function that generates pre-signed S3 POST URLs for secure file uploads.

## Function

- **Handler**: `lambda_function.lambda_handler`
- **Runtime**: Python 3.11
- **Timeout**: 30 seconds

## Environment Variables

- `BUCKET_NAME`: S3 bucket name (set by Terraform)

## Dependencies

See `requirements.txt` (boto3 is included in Lambda runtime by default)

## Local Testing

```python
import json
from lambda_function import lambda_handler

event = {
    'httpMethod': 'POST',
    'body': json.dumps({
        'programme_name': 'TestProgramme',
        'uploaded_by': 'TestUser',
        'filename': 'test.xlsx',
        'file_size': 1024000
    })
}

result = lambda_handler(event, None)
print(result)
```
