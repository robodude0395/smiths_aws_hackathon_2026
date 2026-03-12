import json
import boto3
from datetime import datetime

s3_client = boto3.client('s3', region_name='us-west-2')
BUCKET_NAME = 'comsheet-uploads'

def lambda_handler(event, context):
    """
    Lambda function to list processed files and generate download URLs
    """
    
    # CORS headers
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'GET, OPTIONS'
    }
    
    # Handle OPTIONS request for CORS
    if event.get('httpMethod') == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': headers,
            'body': ''
        }
    
    try:
        # Get query parameters
        params = event.get('queryStringParameters') or {}
        programme_name = params.get('programme_name', '')
        action = params.get('action', 'list')  # 'list' or 'download'
        file_key = params.get('file_key', '')
        
        # Action: List processed files
        if action == 'list':
            # All processed files go in processed/ folder
            prefix = "processed/"
            
            # If programme_name filter is provided, we'll filter in the results
            response = s3_client.list_objects_v2(
                Bucket=BUCKET_NAME,
                Prefix=prefix
            )
            
            files = []
            if 'Contents' in response:
                for obj in response['Contents']:
                    # Skip if it's just the folder itself
                    if obj['Key'] == 'processed/':
                        continue
                    
                    # Get object tags
                    try:
                        tags_response = s3_client.get_object_tagging(
                            Bucket=BUCKET_NAME,
                            Key=obj['Key']
                        )
                        tags = {tag['Key']: tag['Value'] for tag in tags_response['TagSet']}
                    except:
                        tags = {}
                    
                    files.append({
                        'key': obj['Key'],
                        'size': obj['Size'],
                        'last_modified': obj['LastModified'].isoformat(),
                        'programme_name': tags.get('programme_name', ''),
                        'uploaded_by': tags.get('uploaded_by', ''),
                        'upload_timestamp': tags.get('upload_timestamp', ''),
                        'processed_timestamp': tags.get('processed_timestamp', ''),
                        'status': tags.get('status', 'unknown')
                    })
            
            # Filter by programme_name if provided
            if programme_name:
                files = [f for f in files if f['programme_name'].lower() == programme_name.lower()]
            
            # Sort by last modified (newest first)
            files.sort(key=lambda x: x['last_modified'], reverse=True)
            
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({
                    'files': files,
                    'count': len(files)
                })
            }
        
        # Action: Generate download URL
        elif action == 'download':
            if not file_key:
                return error_response('file_key parameter is required', headers)
            
            # Generate pre-signed download URL (valid for 5 minutes)
            download_url = s3_client.generate_presigned_url(
                'get_object',
                Params={
                    'Bucket': BUCKET_NAME,
                    'Key': file_key
                },
                ExpiresIn=300
            )
            
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({
                    'download_url': download_url,
                    'file_key': file_key
                })
            }
        
        else:
            return error_response('Invalid action parameter', headers)
            
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
