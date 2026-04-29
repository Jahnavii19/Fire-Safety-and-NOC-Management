# Firebase Connection and Working Explanation

This document explains in detail how Firebase is connected in this project, how the backend starts, how Firebase Admin SDK is initialized, and how that connection is used by the application.

---

## 1. What Firebase is used for in this project

In this project, Firebase is used mainly for:

- **Cloud Functions** → to host the backend API
- **Firebase Secret Manager integration** → to inject secure environment variables
- **Firebase Admin SDK** → to access Firebase services from the backend
- **Cloud Storage** → to upload and serve files such as NOC PDFs and other uploaded assets

So the backend does **not** connect to Firebase in the same way a frontend app does.

### Frontend Firebase usage
The frontend usually connects using Firebase client SDK configuration like:

```js
const firebaseConfig = {
  apiKey: '...',
  authDomain: '...',
  projectId: '...',
  storageBucket: '...',
  messagingSenderId: '...',
  appId: '...'
};
```

That is **client-side Firebase**.

### Backend Firebase usage in this project
This project uses the **Firebase Admin SDK**, which works differently.

The backend uses code like this:

```js
const admin = require('firebase-admin');
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
});
```

This means:

- the backend authenticates as a trusted server
- it can access Firebase services directly
- it does not need browser Firebase config like `apiKey`
- it uses service account credentials or application default credentials

---

## 2. Main files involved in Firebase connection

The Firebase connection flow is mainly controlled by these files:

- [functions/index.js](functions/index.js)
- [functions/src/config/firebase-admin.js](functions/src/config/firebase-admin.js)
- [functions/src/app.js](functions/src/app.js)
- [functions/src/services/storageService.js](functions/src/services/storageService.js)
- [functions/src/services/nocGenerator.js](functions/src/services/nocGenerator.js)

---

## 3. High-level startup flow

When the backend starts, the connection flow is:

1. Firebase Cloud Function receives a request
2. [functions/index.js](functions/index.js) loads secrets from Firebase Secret Manager
3. `getExpressApp()` is called
4. MongoDB is connected first
5. Firebase Admin SDK is initialized by calling `initFirebase()`
6. Express app is created using `createApp()`
7. Routes start handling requests
8. Any service that needs Firebase Storage calls `getStorage()`

### Simplified flow diagram

```text
Incoming Request
      |
      v
functions/index.js
      |
      +--> connectDB()
      |
      +--> initFirebase()
      |
      +--> createApp()
      |
      v
Express Routes
      |
      v
Services using Firebase Storage
```

---

## 4. How Firebase starts in production

In production, the entry point is [functions/index.js](functions/index.js).

### Important code

```js
const functions = require('firebase-functions/v1');
const createApp = require('./src/app');
const connectDB = require('./src/config/db');
const { initFirebase } = require('./src/config/firebase-admin');

let _expressApp = null;

const getExpressApp = async () => {
  if (_expressApp) return _expressApp;
  await connectDB();
  initFirebase();
  _expressApp = createApp(null);
  return _expressApp;
};

exports.api = functions
  .runWith({ secrets: SECRET_NAMES })
  .https.onRequest(async (req, res) => {
    const app = await getExpressApp();
    return app(req, res);
  });
```

### What this does

#### `runWith({ secrets: SECRET_NAMES })`
This tells Firebase Cloud Functions:

- before the function runs, load the named secrets
- expose those secret values as `process.env.<NAME>`
- make them available securely at runtime

Example secrets used in this project:

```js
const SECRET_NAMES = [
  'MONGODB_URI',
  'JWT_SECRET',
  'JWT_EXPIRES_IN',
  'FIREBASE_PROJECT_ID',
  'FIREBASE_STORAGE_BUCKET',
  'EMAIL_HOST',
  'EMAIL_PORT',
  'EMAIL_USER',
  'EMAIL_PASS',
  'FRONTEND_URL',
  'INSPECTOR_INVITE_CODE',
];
```

#### `getExpressApp()`
This is a **lazy singleton initializer**.

That means:

- on the **first request**, it creates everything
- on later requests, it reuses the already-created Express app
- this improves performance and avoids repeated initialization

The order is important:

```js
await connectDB();
initFirebase();
_expressApp = createApp(null);
```

So:

- first MongoDB connects
- then Firebase Admin SDK initializes
- then Express app is built

---

## 5. How Firebase Admin SDK is initialized

The actual Firebase connection logic is in [functions/src/config/firebase-admin.js](functions/src/config/firebase-admin.js).

### Current code structure

```js
const admin = require('firebase-admin');
const path = require('path');
const logger = require('../utils/logger');

let firebaseApp;

const initFirebase = () => {
  if (firebaseApp) return firebaseApp;

  try {
    const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_KEY;
    const credential = serviceAccountPath
      ? admin.credential.cert(require(path.resolve(serviceAccountPath)))
      : admin.credential.applicationDefault();

    firebaseApp = admin.initializeApp({
      credential,
      storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
    });

    logger.info('Firebase Admin SDK initialized');
  } catch (error) {
    logger.warn(`Firebase Admin SDK not initialized: ${error.message}`);
  }

  return firebaseApp;
};

const getStorage = () => admin.storage().bucket();

module.exports = { initFirebase, getStorage };
```

---

## 6. Detailed explanation of `initFirebase()`

### Step 1: keep a single Firebase app instance

```js
let firebaseApp;
```

This variable stores the initialized Firebase app.

Why this is needed:

- Firebase Admin SDK should not be initialized again and again unnecessarily
- repeated initialization can cause errors or wasted resources
- storing the app in a module variable makes it reusable

### Step 2: prevent duplicate initialization

```js
if (firebaseApp) return firebaseApp;
```

This line checks whether Firebase is already initialized.

If yes:

- return the existing app
- skip reinitialization

This is called a **singleton pattern**.

### Step 3: determine which credential to use

```js
const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_KEY;
const credential = serviceAccountPath
  ? admin.credential.cert(require(path.resolve(serviceAccountPath)))
  : admin.credential.applicationDefault();
```

This is one of the most important parts.

#### Case A: local development with a service account JSON file
If `FIREBASE_SERVICE_ACCOUNT_KEY` exists, the code uses:

```js
admin.credential.cert(...)
```

This means:

- load a Firebase service account JSON file from disk
- create server credentials from that file
- use those credentials to authenticate the backend

Example:

```env
FIREBASE_SERVICE_ACCOUNT_KEY=./serviceAccountKey.json
```

Then this line resolves the file path:

```js
path.resolve(serviceAccountPath)
```

And this loads the JSON:

```js
require(path.resolve(serviceAccountPath))
```

#### Case B: production or cloud runtime
If `FIREBASE_SERVICE_ACCOUNT_KEY` is **not** set, then this is used:

```js
admin.credential.applicationDefault()
```

This means:

- use the runtime environment's default Google credentials
- on Firebase Cloud Functions, these credentials are usually available automatically
- no local JSON file is required in production

This is the preferred and secure cloud-native setup.

### Step 4: initialize Firebase app

```js
firebaseApp = admin.initializeApp({
  credential,
  storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
});
```

This line creates the Firebase Admin app.

Two important things are passed:

#### `credential`
This tells Firebase **who the server is** and allows authentication.

#### `storageBucket`
This tells Firebase which Cloud Storage bucket to use.

Example:

```env
FIREBASE_STORAGE_BUCKET=my-project.appspot.com
```

So after initialization, your backend can talk to:

- Firebase Storage
- and any other Firebase Admin supported services you later add

### Step 5: log the result

```js
logger.info('Firebase Admin SDK initialized');
```

This is useful for debugging and deployment checks.

### Step 6: handle failures safely

```js
} catch (error) {
  logger.warn(`Firebase Admin SDK not initialized: ${error.message}`);
}
```

If initialization fails:

- the app logs a warning
- the failure is visible in logs
- `firebaseApp` stays undefined

This helps identify problems such as:

- bad service account path
- invalid JSON key file
- missing bucket name
- invalid permissions

---

## 7. How `getStorage()` works

The helper is:

```js
const getStorage = () => admin.storage().bucket();
```

This returns the default Cloud Storage bucket configured during `initializeApp()`.

That means this helper gives access to Firebase Storage operations like:

- upload files
- delete files
- generate signed URLs
- access bucket file references

---

## 8. How Firebase Storage is used in this project

Firebase is not only initialized — it is actively used by services.

### Example 1: file upload service
File: [functions/src/services/storageService.js](functions/src/services/storageService.js)

```js
const { getStorage } = require('../config/firebase-admin');

const uploadFile = async (buffer, filename, contentType, folder = 'uploads') => {
  const storage = getStorage();
  const destination = `${folder}/${Date.now()}-${filename}`;
  const file = storage.file(destination);

  await file.save(buffer, { contentType, public: true });
  const [url] = await file.getSignedUrl({
    action: 'read',
    expires: '01-01-2100',
  });

  return url;
};
```

### Detailed working

#### `const storage = getStorage();`
Gets the Firebase Storage bucket object.

#### `const destination = ...`
Creates a unique file path inside the bucket.

Example result:

```text
uploads/1712570000000-report.pdf
```

#### `const file = storage.file(destination);`
Creates a file reference inside the bucket.

#### `await file.save(buffer, { contentType, public: true });`
Uploads the raw file buffer to Cloud Storage.

#### `await file.getSignedUrl(...)`
Creates a signed public URL so the file can be accessed later.

---

### Example 2: NOC PDF upload
File: [functions/src/services/nocGenerator.js](functions/src/services/nocGenerator.js)

```js
if (process.env.FIREBASE_STORAGE_BUCKET) {
  const storage = getStorage();
  const destination = `noc-certificates/${certificate.certificateNumber}.pdf`;
  await storage.upload(tmpFile, { destination, public: true });
  const [url] = await storage.file(destination).getSignedUrl({
    action: 'read',
    expires: '01-01-2100',
  });
  return url;
}
```

### What happens here

- PDF is generated locally into a temp file
- Firebase Storage bucket is obtained
- temp file is uploaded to bucket
- signed URL is created
- URL is saved/returned for later access

This is a very common backend Firebase Storage workflow.

---

## 9. Local development Firebase connection

When running locally, [functions/index.js](functions/index.js) has this block:

```js
if (require.main === module) {
  require('dotenv').config();

  const http = require('http');
  const { Server } = require('socket.io');
  const logger = require('./src/utils/logger');

  const PORT = process.env.PORT || 5000;

  const server = http.createServer();
  const io = new Server(server, {
    cors: {
      origin: (process.env.FRONTEND_URL || 'http://localhost:3000')
        .split(',')
        .map((o) => o.trim()),
      methods: ['GET', 'POST'],
    },
  });

  const app = createApp(io);
  server.on('request', app);

  const startServer = async () => {
    try {
      await connectDB();
      initFirebase();
      server.listen(PORT, () => logger.info(`BLAZE dev server running on port ${PORT}`));
    } catch (error) {
      require('./src/utils/logger').error(`Server startup error: ${error.message}`);
      process.exit(1);
    }
  };

  startServer();
}
```

### Local flow explanation

When you run:

```bash
node index.js
```

or

```bash
npm run dev
```

this block runs.

Then the app does:

1. load environment values from `.env`
2. create HTTP server
3. create Socket.IO server
4. create Express app
5. connect MongoDB
6. initialize Firebase Admin SDK
7. start server listening on a port

So even in local mode, Firebase is initialized using the same `initFirebase()` logic.

The difference is only where credentials come from.

---

## 10. Difference between local and production Firebase authentication

### Local
Usually uses:

```js
admin.credential.cert(serviceAccountJson)
```

You manually provide a service account JSON path.

### Production
Usually uses:

```js
admin.credential.applicationDefault()
```

Firebase/Google runtime automatically provides secure credentials.

### Summary table

| Environment | Credential Source | Typical Usage |
|---|---|---|
| Local development | Service account JSON file | Testing backend on your machine |
| Firebase Cloud Functions | Application default credentials | Production deployment |

---

## 11. Why `initFirebase()` is called before storage operations

Services like [functions/src/services/storageService.js](functions/src/services/storageService.js) depend on:

```js
admin.storage().bucket()
```

If Firebase is not initialized first, Storage access may fail.

That is why [functions/index.js](functions/index.js) calls:

```js
initFirebase();
```

before requests are handled.

This ensures the backend is ready to use Firebase services when controllers and services run.

---

## 12. End-to-end request example

Let us take a real example.

### Scenario: issuing an NOC certificate

1. Client sends request to issue a certificate
2. Route hits controller
3. Controller generates QR code and PDF
4. PDF service calls Firebase Storage
5. Firebase returns signed URL
6. URL is stored in database and returned to client

### Flow with code responsibility

#### Step 1: Cloud Function entry
[functions/index.js](functions/index.js)

```js
const app = await getExpressApp();
return app(req, res);
```

#### Step 2: Firebase initialized
[functions/src/config/firebase-admin.js](functions/src/config/firebase-admin.js)

```js
firebaseApp = admin.initializeApp({
  credential,
  storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
});
```

#### Step 3: Storage bucket accessed
[functions/src/services/nocGenerator.js](functions/src/services/nocGenerator.js)

```js
const storage = getStorage();
await storage.upload(tmpFile, { destination, public: true });
```

#### Step 4: Signed URL generated

```js
const [url] = await storage.file(destination).getSignedUrl({
  action: 'read',
  expires: '01-01-2100',
});
```

#### Step 5: final result
The backend now has a public URL to the uploaded PDF.

---

## 13. Example minimal Firebase Admin connection snippet

If you want a small standalone example, it looks like this:

```js
const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
});

const bucket = admin.storage().bucket();

async function testUpload() {
  const file = bucket.file('sample/test.txt');
  await file.save(Buffer.from('Hello Firebase Storage'), {
    contentType: 'text/plain',
    public: true,
  });

  const [url] = await file.getSignedUrl({
    action: 'read',
    expires: '01-01-2100',
  });

  console.log('Uploaded file URL:', url);
}

testUpload();
```

---

## 14. Example `.env` values for local development

Example local configuration:

```env
MONGODB_URI=mongodb+srv://username:password@cluster.mongodb.net/blaze
JWT_SECRET=your_jwt_secret
JWT_EXPIRES_IN=7d
FIREBASE_STORAGE_BUCKET=your-project.appspot.com
FIREBASE_SERVICE_ACCOUNT_KEY=./serviceAccountKey.json
FRONTEND_URL=http://localhost:3000
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USER=example@gmail.com
EMAIL_PASS=app_password
INSPECTOR_INVITE_CODE=invite_code_here
```

---

## 15. Common issues and debugging

### Problem: Firebase Admin SDK not initialized
Possible reasons:

- wrong `FIREBASE_SERVICE_ACCOUNT_KEY` path
- invalid JSON service account file
- missing `FIREBASE_STORAGE_BUCKET`
- insufficient IAM permissions

### Problem: storage upload fails
Possible reasons:

- Firebase bucket name is wrong
- service account does not have Storage access
- Firebase app was not initialized before file upload

### Problem: works locally but not in production
Possible reasons:

- secrets not configured in Firebase Secret Manager
- wrong project or bucket settings
- missing runtime permissions

### Useful log line

```js
logger.info('Firebase Admin SDK initialized');
```

If this log never appears, initialization likely failed.

---

## 16. Why this project uses Firebase Admin SDK instead of frontend SDK

Because this is a backend server.

The backend needs:

- trusted access
- secure file upload capability
- server-side credentials
- no exposure of secrets to the browser

So the correct choice is **Firebase Admin SDK**.

The frontend SDK is for browser or mobile client apps.

---

## 17. Final summary

### In one sentence
This project connects to Firebase by initializing the **Firebase Admin SDK** in the backend using either a **service account JSON file** or **application default credentials**, and then uses that initialized app mainly for **Cloud Storage operations**.

### Main connection chain

```text
functions/index.js
   -> initFirebase()
   -> firebase-admin initializeApp()
   -> getStorage()
   -> upload/download files from Firebase Storage
```

### Most important code snippet

```js
const credential = serviceAccountPath
  ? admin.credential.cert(require(path.resolve(serviceAccountPath)))
  : admin.credential.applicationDefault();

firebaseApp = admin.initializeApp({
  credential,
  storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
});
```

This is the core of the Firebase connection in your backend.

---

## 18. Related files to read next

If you want to understand the full flow even deeper, read these files in order:

1. [functions/index.js](functions/index.js)
2. [functions/src/config/firebase-admin.js](functions/src/config/firebase-admin.js)
3. [functions/src/app.js](functions/src/app.js)
4. [functions/src/services/storageService.js](functions/src/services/storageService.js)
5. [functions/src/services/nocGenerator.js](functions/src/services/nocGenerator.js)

---

If needed, this document can later be expanded with:

- Firebase Hosting explanation
- Firebase Cloud Messaging explanation
- client-side Firebase setup explanation
- deployment steps with Firebase CLI
