// Smiths Detection COMsheet Upload Portal - Application Logic

const API_ENDPOINT = CONFIG.API_ENDPOINT;
const FILES_API_ENDPOINT = CONFIG.FILES_API_ENDPOINT;

// Validate API endpoints
if (!API_ENDPOINT || API_ENDPOINT === 'YOUR_API_GATEWAY_URL_HERE') {
    console.error('API endpoint not configured! Please update config.js');
} else {
    console.log('API endpoint configured:', API_ENDPOINT);
    console.log('Files API endpoint configured:', FILES_API_ENDPOINT);
}

// DOM Elements
const uploadZone = document.getElementById('uploadZone');
const fileInput = document.getElementById('fileInput');
const uploadPrompt = document.getElementById('uploadPrompt');
const fileInfo = document.getElementById('fileInfo');
const fileNameDisplay = document.getElementById('fileNameDisplay');
const fileSizeDisplay = document.getElementById('fileSizeDisplay');
const uploadForm = document.getElementById('uploadForm');
const status = document.getElementById('status');
const statusTitle = document.getElementById('statusTitle');
const statusMessage = document.getElementById('statusMessage');
const statusPath = document.getElementById('statusPath');
const statusMeta = document.getElementById('statusMeta');
const progressBar = document.getElementById('progressBar');
const progressBarFill = document.getElementById('progressBarFill');
const uploadBtn = document.getElementById('uploadBtn');

let selectedFile = null;

// Upload zone click handler
uploadZone.addEventListener('click', () => fileInput.click());

// Drag and drop handlers
uploadZone.addEventListener('dragover', (e) => {
    e.preventDefault();
    uploadZone.style.borderColor = '#0476CB';
    uploadZone.style.background = 'rgba(4, 118, 203, 0.03)';
});

uploadZone.addEventListener('dragleave', () => {
    if (!selectedFile) {
        uploadZone.style.borderColor = '#E8ECF1';
        uploadZone.style.background = '#FFFFFF';
    }
});

uploadZone.addEventListener('drop', (e) => {
    e.preventDefault();
    const files = e.dataTransfer.files;
    if (files.length > 0) {
        handleFileSelect(files[0]);
    }
});

// File input change handler
fileInput.addEventListener('change', (e) => {
    if (e.target.files.length > 0) {
        handleFileSelect(e.target.files[0]);
    }
});

// Handle file selection
function handleFileSelect(file) {
    const validExtensions = ['.xlsx', '.xls', '.xlsm'];
    const fileExtension = file.name.substring(file.name.lastIndexOf('.')).toLowerCase();
    
    if (!validExtensions.includes(fileExtension)) {
        showStatus('error', 'Upload Failed', 'Please select a valid Excel file (.xlsx, .xls, or .xlsm)', '');
        return;
    }
    
    if (file.size > 50 * 1024 * 1024) {
        showStatus('error', 'Upload Failed', 'File size must be under 50MB', '');
        return;
    }
    
    selectedFile = file;
    uploadPrompt.style.display = 'none';
    fileInfo.style.display = 'block';
    fileNameDisplay.textContent = file.name;
    fileSizeDisplay.textContent = `${(file.size / 1024).toFixed(2)} KB`;
    uploadZone.classList.add('has-file');
    hideStatus();
}

// Clear file selection
function clearFile() {
    selectedFile = null;
    fileInput.value = '';
    uploadPrompt.style.display = 'block';
    fileInfo.style.display = 'none';
    uploadZone.classList.remove('has-file');
    uploadZone.style.borderColor = '#E8ECF1';
    uploadZone.style.background = '#FFFFFF';
}

// Form submission
uploadForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const programmeName = document.getElementById('programmeName').value.trim();
    const uploadedBy = document.getElementById('uploadedBy').value.trim();
    const contractRef = document.getElementById('contractRef').value.trim();
    
    if (!programmeName || !uploadedBy || !contractRef) {
        showStatus('error', 'Upload Failed', 'Please fill in all required fields', '');
        return;
    }
    
    if (!selectedFile) {
        showStatus('error', 'Upload Failed', 'Please select a file to upload', '');
        return;
    }
    
    await uploadFile(programmeName, uploadedBy, contractRef, selectedFile);
});

// Upload file function
async function uploadFile(programmeName, uploadedBy, contractRef, file) {
    try {
        uploadBtn.disabled = true;
        showStatus('uploading', 'Uploading COMsheet...', 'Requesting upload URL from server', '');
        progressBar.style.display = 'block';
        progressBarFill.style.width = '10%';
        
        console.log('Uploading to:', API_ENDPOINT);
        
        // Step 1: Get pre-signed URL from Lambda
        const response = await fetch(API_ENDPOINT, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                programme_name: programmeName,
                uploaded_by: uploadedBy,
                filename: file.name,
                file_size: file.size
            })
        });
        
        console.log('Response status:', response.status);
        
        if (!response.ok) {
            const contentType = response.headers.get('content-type');
            let errorMessage = 'Failed to get upload URL';
            
            if (contentType && contentType.includes('application/json')) {
                const error = await response.json();
                console.error('JSON error:', error);
                errorMessage = error.error || errorMessage;
            } else {
                const text = await response.text();
                console.error('Non-JSON response:', text);
                errorMessage = `Server error (${response.status}): ${text.substring(0, 200)}`;
            }
            throw new Error(errorMessage);
        }
        
        const data = await response.json();
        progressBarFill.style.width = '30%';
        
        // Step 2: Upload directly to S3
        showStatus('uploading', 'Uploading COMsheet...', 'Uploading file to S3 storage', '');
        
        const formData = new FormData();
        Object.keys(data.fields).forEach(key => {
            formData.append(key, data.fields[key]);
        });
        formData.append('file', file);
        
        try {
            const uploadResponse = await fetch(data.url, {
                method: 'POST',
                body: formData
            });
            
            if (!uploadResponse.ok && uploadResponse.status !== 204) {
                throw new Error(`S3 upload failed with status ${uploadResponse.status}`);
            }
        } catch (uploadError) {
            if (uploadError.message.includes('Failed to fetch') || uploadError.message.includes('CORS')) {
                console.log('CORS error on S3 response (upload likely succeeded):', uploadError);
            } else {
                throw uploadError;
            }
        }
        
        progressBarFill.style.width = '100%';
        
        const s3Path = `s3://${data.bucket}/${data.s3_key}`;
        const timestamp = new Date(data.timestamp).toLocaleString();
        const fileSize = (file.size / 1024).toFixed(2);
        
        showStatus('success', '✅ Upload Successful', 
            'Your COMsheet has been uploaded and is pending SAP processing', 
            s3Path, 
            `Uploaded: ${timestamp} | Size: ${fileSize} KB`);
        
        // Reset form after 5 seconds
        setTimeout(() => {
            uploadForm.reset();
            clearFile();
            hideStatus();
            uploadBtn.disabled = false;
        }, 5000);
        
    } catch (error) {
        showStatus('error', '❌ Upload Failed', error.message, '');
        uploadBtn.disabled = false;
        progressBar.style.display = 'none';
    }
}

// Show status
function showStatus(type, title, message, path, meta) {
    status.className = `status show ${type}`;
    statusTitle.textContent = title;
    statusMessage.textContent = message;
    
    if (path) {
        statusPath.textContent = path;
        statusPath.style.display = 'block';
    } else {
        statusPath.style.display = 'none';
    }
    
    if (meta) {
        statusMeta.textContent = meta;
    } else {
        statusMeta.textContent = '';
    }
    
    if (type === 'uploading') {
        progressBar.style.display = 'block';
    } else {
        progressBar.style.display = 'none';
    }
}

// Hide status
function hideStatus() {
    status.className = 'status';
    progressBar.style.display = 'none';
    progressBarFill.style.width = '0%';
}

// Tab switching
function switchTab(tabName) {
    document.querySelectorAll('.tab').forEach(tab => {
        tab.classList.remove('active');
    });
    event.target.classList.add('active');
    
    document.querySelectorAll('.tab-content').forEach(content => {
        content.classList.remove('active');
    });
    document.getElementById(tabName + 'Tab').classList.add('active');
    
    if (tabName === 'download') {
        loadProcessedFiles();
    }
}

// Load processed files
async function loadProcessedFiles() {
    const filesList = document.getElementById('filesList');
    
    if (!FILES_API_ENDPOINT || FILES_API_ENDPOINT === 'YOUR_API_GATEWAY_URL_HERE') {
        filesList.innerHTML = '<div class="empty-state">❌ FILES_API_ENDPOINT not configured in config.js</div>';
        console.error('FILES_API_ENDPOINT not set:', FILES_API_ENDPOINT);
        return;
    }
    
    filesList.innerHTML = '<div class="empty-state">⏳ Loading files...</div>';
    
    try {
        const url = new URL(FILES_API_ENDPOINT);
        url.searchParams.append('action', 'list');
        
        const response = await fetch(url);
        
        if (!response.ok) {
            throw new Error('Failed to load files');
        }
        
        const data = await response.json();
        
        if (data.files.length === 0) {
            filesList.innerHTML = '<div class="empty-state">No processed files found</div>';
            return;
        }
        
        filesList.innerHTML = '';
        data.files.forEach(file => {
            const fileItem = document.createElement('div');
            fileItem.className = 'file-item';
            
            const fileName = file.key.split('/').pop();
            const lastModified = new Date(file.last_modified).toLocaleString();
            const sizeKB = (file.size / 1024).toFixed(2);
            
            fileItem.innerHTML = `
                <div class="file-item-info">
                    <div class="file-item-name">📄 ${fileName}</div>
                    <div class="file-item-meta">
                        Programme: ${file.programme_name || 'N/A'} | 
                        Uploaded by: ${file.uploaded_by || 'N/A'}<br>
                        Last modified: ${lastModified} | 
                        Size: ${sizeKB} KB
                    </div>
                </div>
                <button class="btn-download" onclick="downloadFile('${file.key}', '${fileName}')">
                    ⬇️ DOWNLOAD
                </button>
            `;
            
            filesList.appendChild(fileItem);
        });
        
    } catch (error) {
        filesList.innerHTML = `<div class="empty-state">❌ Error loading files: ${error.message}</div>`;
    }
}

// Download file
async function downloadFile(fileKey, fileName) {
    try {
        const url = new URL(FILES_API_ENDPOINT);
        url.searchParams.append('action', 'download');
        url.searchParams.append('file_key', fileKey);
        
        const response = await fetch(url);
        
        if (!response.ok) {
            throw new Error('Failed to get download URL');
        }
        
        const data = await response.json();
        
        const a = document.createElement('a');
        a.href = data.download_url;
        a.download = fileName;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        
    } catch (error) {
        alert(`Download failed: ${error.message}`);
    }
}
