import json
import boto3
import os
from datetime import datetime
from urllib.parse import quote

s3_client = boto3.client('s3', region_name='us-west-2')
BUCKET_NAME = 'comsheet-uploads'
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB

def lambda_handler(event, context):
    """
    Lambda function to generate pre-signed POST URL for S3 upload
    """
    
    # CORS headers
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'POST, OPTIONS'
    }
    
    # Handle OPTIONS request for CORS
    if event.get('httpMethod') == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': headers,
            'body': ''
        }
    
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        programme_name = body.get('programme_name', '').strip()
        uploaded_by = body.get('uploaded_by', '').strip()
        filename = body.get('filename', '').strip()
        file_size = body.get('file_size', 0)
        
        # Validation
        if not programme_name:
            return error_response('Programme name is required', headers)
        
        if not uploaded_by:
            return error_response('Uploaded by is required', headers)
        
        if not filename:
            return error_response('Filename is required', headers)
        
        # Validate file extension
        valid_extensions = ('.xlsx', '.xls', '.xlsm')
        if not filename.lower().endswith(valid_extensions):
            return error_response('File must be .xlsx, .xls, or .xlsm', headers)
        
        # Validate file size
        if file_size > MAX_FILE_SIZE:
            return error_response('File size must be under 50MB', headers)
        
        # Generate S3 key
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        upload_timestamp = datetime.utcnow().isoformat() + 'Z'
        
        # Sanitize programme_name for S3 path
        safe_programme_name = programme_name.replace('/', '_').replace('\\', '_')
        s3_key = f"pending/{safe_programme_name}/{timestamp}_{filename}"
        
        # Generate pre-signed POST URL
        presigned_post = s3_client.generate_presigned_post(
            Bucket=BUCKET_NAME,
            Key=s3_key,
            Fields={
                'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                'x-amz-tagging': f'programme_name={quote(programme_name)}&uploaded_by={quote(uploaded_by)}&upload_timestamp={quote(upload_timestamp)}&status=pending_transform'
            },
            Conditions=[
                {'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'},
                ['content-length-range', 1, MAX_FILE_SIZE],
                {'x-amz-tagging': f'programme_name={quote(programme_name)}&uploaded_by={quote(uploaded_by)}&upload_timestamp={quote(upload_timestamp)}&status=pending_transform'}
            ],
            ExpiresIn=300  # URL valid for 5 minutes
        )
        
        # Use regional S3 endpoint to avoid 307 redirects
        regional_url = f'https://{BUCKET_NAME}.s3.us-west-2.amazonaws.com/'
        presigned_post['url'] = regional_url
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'url': presigned_post['url'],
                'fields': presigned_post['fields'],
                's3_key': s3_key,
                'bucket': BUCKET_NAME,
                'timestamp': upload_timestamp
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return error_response(f'Internal server error: {str(e)}', headers)

def error_response(message, headers):
    """Helper function to return error response"""
    return {
        'statusCode': 400,
        'headers': headers,
        'body': json.dumps({'error': message})
    }
