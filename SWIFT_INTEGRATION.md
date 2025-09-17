# Swift App Integration Guide for Image Similarity Server

## Overview
The Image Similarity Server runs separately from the main FastAPI server on port 8001 and handles all image similarity calculations for the UWB Navigator system.

## Server Details
- **Port**: 8001
- **Main Endpoint**: `http://localhost:8001/api/similarity`
- **Base64 Endpoint**: `http://localhost:8001/api/similarity-base64`
- **Bonjour Service**: `_uwb-similarity._tcp.local.`

## Swift Integration

### 1. Service Discovery via Bonjour
```swift
// Look for service: _uwb-similarity._tcp.local.
let browser = NetServiceBrowser()
browser.searchForServices(ofType: "_uwb-similarity._tcp.", inDomain: "local.")
```

### 2. Sending Images - Option A: Multipart Form Data
```swift
func sendImageMultipart(image: UIImage, location: String, navigatorId: String, navigatorName: String) {
    guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }

    let url = URL(string: "http://similarity-server:8001/api/similarity")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    let boundary = UUID().uuidString
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    var body = Data()

    // Add image
    body.append("--\(boundary)\r\n")
    body.append("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n")
    body.append("Content-Type: image/jpeg\r\n\r\n")
    body.append(imageData)
    body.append("\r\n")

    // Add location
    body.append("--\(boundary)\r\n")
    body.append("Content-Disposition: form-data; name=\"location\"\r\n\r\n")
    body.append("\(location)\r\n")

    // Add navigator_id
    body.append("--\(boundary)\r\n")
    body.append("Content-Disposition: form-data; name=\"navigator_id\"\r\n\r\n")
    body.append("\(navigatorId)\r\n")

    // Add navigator_name
    body.append("--\(boundary)\r\n")
    body.append("Content-Disposition: form-data; name=\"navigator_name\"\r\n\r\n")
    body.append("\(navigatorName)\r\n")

    body.append("--\(boundary)--\r\n")

    request.httpBody = body

    URLSession.shared.dataTask(with: request) { data, response, error in
        // Handle response
    }.resume()
}
```

### 3. Sending Images - Option B: Base64 Encoding
```swift
func sendImageBase64(image: UIImage, location: String, navigatorId: String, navigatorName: String) {
    guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
    let base64String = imageData.base64EncodedString()

    let url = URL(string: "http://similarity-server:8001/api/similarity-base64")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    var components = URLComponents()
    components.queryItems = [
        URLQueryItem(name: "image_base64", value: base64String),
        URLQueryItem(name: "location", value: location),
        URLQueryItem(name: "navigator_id", value: navigatorId),
        URLQueryItem(name: "navigator_name", value: navigatorName)
    ]

    request.httpBody = components.query?.data(using: .utf8)

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let similarityScore = json["similarity_score"] as? Double ?? 0.0
            print("Similarity: \(similarityScore)%")
        }
    }.resume()
}
```

## Supported Locations
The server recognizes these location values:
- `"Kitchen"`
- `"Meeting Room"`
- `"Window"`

## Response Format
```json
{
    "success": true,
    "similarity_score": 85.5,
    "navigator_id": "nav_001",
    "navigator_name": "John's iPhone",
    "location": "Kitchen",
    "timestamp": "2025-09-17T15:30:00.000Z",
    "message": "Similarity calculated: 85.5%",
    "contract": {  // Only if score >= 50%
        "txId": "0x12345678",
        "navigatorId": "John's iPhone",
        "similarityScore": 85.5,
        "qodQuorum": "Pass",
        // ... other contract fields
    }
}
```

## Error Handling
```swift
// Handle different status codes
switch (response as? HTTPURLResponse)?.statusCode {
case 200:
    // Success
case 400:
    // Bad request (invalid location, missing parameters)
case 500:
    // Server error
default:
    // Network or other error
}
```

## Image Requirements
- **Formats**: JPEG, PNG, HEIC (convert HEIC to JPEG before sending)
- **Recommended Size**: Compress images to reasonable size (< 5MB)
- **Quality**: Use 0.8 compression quality for good balance

## Testing
To test the integration:
1. Start the similarity server: `python3 similarity_server.py`
2. Use the test endpoint: `POST http://localhost:8001/api/test-similarity`
3. Check server logs for debugging

## Important Notes
1. The server runs independently from the main FastAPI server
2. Make sure the similarity server is running before sending requests
3. The server automatically notifies the webapp when similarity is calculated
4. Use Bonjour/mDNS for automatic server discovery
5. CORS is enabled for all origins