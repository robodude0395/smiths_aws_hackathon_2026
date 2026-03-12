# Frontend

Single-page HTML application for uploading Excel files.

## Setup

1. After deploying infrastructure, copy the example config:
   ```bash
   cp config.example.js config.js
   ```

2. Update `config.js` with your API endpoint from Terraform output:
   ```javascript
   const CONFIG = {
       API_ENDPOINT: 'https://your-api-id.execute-api.us-west-2.amazonaws.com/prod/upload'
   };
   ```

3. Open `index.html` in a browser or serve it locally:
   ```bash
   python3 -m http.server 8000
   ```

## Features

- Drag-and-drop file upload
- File type validation (.xlsx, .xls only)
- File size validation (max 50MB)
- Real-time upload progress
- Direct upload to S3 via pre-signed URLs

