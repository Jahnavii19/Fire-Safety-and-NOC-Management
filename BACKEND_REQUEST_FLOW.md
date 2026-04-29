# Backend Request Flow and Firebase — Detailed Explanation

This document explains end-to-end how every API request is received, processed, and responded to in the BLAZE backend.  It also explains in full detail how Firebase is connected and used across the system.

---

## Table of Contents

1. [Big Picture Architecture](#1-big-picture-architecture)
2. [Entry Point — index.js](#2-entry-point--indexjs)
3. [Firebase Startup and Initialization](#3-firebase-startup-and-initialization)
4. [Express App Creation — app.js](#4-express-app-creation--appjs)
5. [The 10-Layer Middleware Stack](#5-the-10-layer-middleware-stack)
6. [Route Matching](#6-route-matching)
7. [Authentication Middleware — JWT Flow](#7-authentication-middleware--jwt-flow)
8. [Authorization Middleware — RBAC](#8-authorization-middleware--rbac)
9. [Request Validation](#9-request-validation)
10. [Controller Execution](#10-controller-execution)
11. [Database Interaction — MongoDB](#11-database-interaction--mongodb)
12. [Services Layer](#12-services-layer)
13. [Firebase Storage In-Depth](#13-firebase-storage-in-depth)
14. [Error Handling](#14-error-handling)
15. [Response Journey](#15-response-journey)
16. [Cold Start vs Warm Start](#16-cold-start-vs-warm-start)
17. [Real-Time Events — Socket.IO](#17-real-time-events--socketio)
18. [Full End-to-End Trace — Real Example](#18-full-end-to-end-trace--real-example)
19. [Local Development Mode](#19-local-development-mode)
20. [Firebase Detailed Internals](#20-firebase-detailed-internals)

---

## 1. Big Picture Architecture

Before going into code, understand the overall architecture.

```text
  [Browser / Mobile App]
          |
          | HTTPS request
          v
  [Firebase Cloud Functions]  ← production entry point
          |
   index.js receives request
          |
          +--> getExpressApp() on cold start:
          |      |
          |      +--> connectDB()       ← MongoDB Atlas
          |      +--> initFirebase()    ← Firebase Admin SDK
          |      +--> createApp(null)   ← Express app
          |
   Express app processes request
          |
          +--> CORS middleware
          +--> Helmet (security headers)
          +--> Morgan (logging)
          +--> Body parser
          +--> Mongo sanitize
          +--> Rate limiter
          +--> Socket.IO injection (if dev)
          +--> Route matching
                 |
                 +--> authenticate (JWT check)
                 +--> authorize (role check)
                 +--> validate (input validation)
                 +--> Controller function
                        |
                        +--> Model (MongoDB query)
                        +--> Service (email / storage / audit)
                        +--> return JSON response
          |
          +--> notFound (if no route matched)
          +--> errorHandler (if error thrown)
          |
          v
  [Response back to client]
```

Every single request follows this chain from top to bottom.

---

## 2. Entry Point — index.js

File: [functions/index.js](functions/index.js)

This file is the absolute entry point for the backend.

### In production (Firebase Cloud Functions)

When a request arrives, Firebase invokes `exports.api`.

```js
exports.api = functions
  .runWith({ secrets: SECRET_NAMES })
  .https.onRequest(async (req, res) => {
    const app = await getExpressApp();
    return app(req, res);
  });
```

### What happens step by step

#### Step 1 — Firebase loads secrets

```js
.runWith({ secrets: SECRET_NAMES })
```

`SECRET_NAMES` is this array:

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

Before the function handler runs, Firebase Secret Manager reads each secret by name and injects it as an environment variable.

For example:

```
process.env.MONGODB_URI        = "mongodb+srv://..."
process.env.JWT_SECRET         = "your_secret_key"
process.env.FIREBASE_STORAGE_BUCKET = "your-project.appspot.com"
```

This means no secrets are hardcoded.  They are stored safely in Firebase Secret Manager and only available at runtime.

#### Step 2 — `getExpressApp()` is called

```js
const getExpressApp = async () => {
  if (_expressApp) return _expressApp;
  await connectDB();
  initFirebase();
  _expressApp = createApp(null);
  return _expressApp;
};
```

This is a **lazy singleton**.

- if the function is already warmed up and `_expressApp` exists, skip initialization and reuse it
- if it is a cold start, run the full initialization chain

The initialization order is:

```
connectDB()   →   initFirebase()   →   createApp(null)
```

This order matters because services later in the chain depend on MongoDB and Firebase being ready.

#### Step 3 — request is handed to Express

```js
return app(req, res);
```

From here, Express takes over completely.

---

## 3. Firebase Startup and Initialization

File: [functions/src/config/firebase-admin.js](functions/src/config/firebase-admin.js)

### Full code

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

### Detailed breakdown

#### Why `let firebaseApp` at module level?

```js
let firebaseApp;
```

The module is loaded once per Node.js process.  This variable persists across all requests during a warm invocation.

#### Singleton check

```js
if (firebaseApp) return firebaseApp;
```

If Firebase was already initialized in a previous request on the same warm instance, return it immediately.  Skip all initialization code.

This prevents the error `Firebase App named '[DEFAULT]' already exists`.

#### Credential resolution

```js
const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_KEY;
const credential = serviceAccountPath
  ? admin.credential.cert(require(path.resolve(serviceAccountPath)))
  : admin.credential.applicationDefault();
```

Two modes:

**Local development:**

If `FIREBASE_SERVICE_ACCOUNT_KEY` is set to a file path in your `.env`:

```env
FIREBASE_SERVICE_ACCOUNT_KEY=./serviceAccountKey.json
```

Then:

```js
admin.credential.cert(require(path.resolve('./serviceAccountKey.json')))
```

- `path.resolve()` converts relative path to absolute
- `require()` parses the JSON file
- `admin.credential.cert()` creates server credentials from the JSON

The JSON file looks like this:

```json
{
  "type": "service_account",
  "project_id": "your-project",
  "private_key_id": "...",
  "private_key": "-----BEGIN RSA PRIVATE KEY-----\n...",
  "client_email": "firebase-adminsdk-xyz@your-project.iam.gserviceaccount.com",
  "client_id": "...",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}
```

**Production (Cloud Functions):**

If no path is set:

```js
admin.credential.applicationDefault()
```

Google Cloud detects credentials automatically from the runtime environment.  On Firebase Cloud Functions, the underlying compute already has the project's service account bound to it.  No file is needed.

#### Firebase initialization

```js
firebaseApp = admin.initializeApp({
  credential,
  storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
});
```

Two things configured:

- `credential` — proves who the server is
- `storageBucket` — tells Firebase which storage bucket to use (e.g. `my-project.appspot.com`)

After this, the `admin` global object is connected to your project.

#### Getting the storage bucket

```js
const getStorage = () => admin.storage().bucket();
```

Every service that needs to upload or download files calls `getStorage()` to get the bucket reference.

---

## 4. Express App Creation — app.js

File: [functions/src/app.js](functions/src/app.js)

`createApp(io)` is the factory function that builds the fully configured Express application.

### Full creation flow

```js
const createApp = (io) => {
  const app = express();

  app.set('trust proxy', 1);

  // CORS
  app.use(cors({ ... }));

  // Security headers
  app.use(helmet({ ... }));

  // HTTP request logging
  app.use(morgan(...));

  // Parse JSON and form bodies
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true, limit: '10mb' }));

  // Strip NoSQL injection characters
  app.use(mongoSanitize());

  // Global rate limiter
  app.use(defaultLimiter);

  // Inject Socket.IO into every request
  if (io) {
    app.use((req, _res, next) => {
      req.io = io;
      next();
    });
  }

  // Health check
  app.get('/health', (req, res) => {
    res.json({ success: true, message: 'BLAZE API is running', version: '1.0.0' });
  });

  // Route mounting
  app.use('/api/auth', authRoutes);
  app.use('/api/applications', applicationsRoutes);
  app.use('/api/inspections', inspectionsRoutes);
  app.use('/api/incidents', incidentsRoutes);
  app.use('/api/noc', nocRoutes);
  app.use('/api/analytics', analyticsRoutes);

  // 404 and error handlers
  app.use(notFound);
  app.use(errorHandler);

  return app;
};
```

Each route group is an `express.Router()` with its own middleware chain.

---

## 5. The 10-Layer Middleware Stack

Every request passes through these layers in order before a controller runs.

```
Layer 1 → trust proxy
Layer 2 → CORS check
Layer 3 → Helmet security headers
Layer 4 → Morgan HTTP logging
Layer 5 → Body parser (JSON / URL-encoded)
Layer 6 → Mongo sanitize
Layer 7 → Rate limiter
Layer 8 → Socket.IO injection (dev only)
Layer 9 → Route-level middleware (authenticate, authorize, validate)
Layer 10 → Controller handler
```

### Layer 1 — trust proxy

```js
app.set('trust proxy', 1);
```

Firebase Cloud Functions sit behind a Google load balancer.  Without this, `req.ip` would always return the load balancer's IP instead of the real client IP.  The rate limiter uses `req.ip` to track request counts per client.

### Layer 2 — CORS

```js
app.use(cors({
  origin: (origin, callback) => {
    if (!origin || allowedOrigins.includes(origin)) return callback(null, true);
    callback(new Error(`CORS blocked: ${origin}`));
  },
  credentials: true,
}));
```

`FRONTEND_URL` is read from env (supports multiple origins separated by commas).  Only requests from allowed origins are accepted.  `credentials: true` allows cookies and Authorization headers.

### Layer 3 — Helmet

```js
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'unsafe-inline'", 'https://cdnjs.cloudflare.com'],
      ...
    }
  },
  crossOriginEmbedderPolicy: false,
}));
```

Helmet sets HTTP headers that prevent common attacks:

- `X-Content-Type-Options: nosniff` — prevents MIME sniffing
- `X-Frame-Options: SAMEORIGIN` — prevents clickjacking
- `Content-Security-Policy` — restricts which resources the browser can load

### Layer 4 — Morgan

```js
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev'));
```

Logs every request.

- `dev` format in development: `GET /api/applications 200 45ms`
- `combined` format in production: Apache-style logs with IP, User-Agent, etc.

### Layer 5 — Body Parser

```js
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
```

Parses the raw request body into `req.body`.

- `express.json()` handles `Content-Type: application/json`
- `express.urlencoded()` handles form submissions
- `limit: '10mb'` allows file uploads up to 10 MB

### Layer 6 — Mongo Sanitize

```js
app.use(mongoSanitize());
```

Strips `$` and `.` from all request inputs (`req.body`, `req.params`, `req.query`).

Without this, an attacker could send:

```json
{ "email": { "$gt": "" }, "password": { "$gt": "" } }
```

and bypass authentication via a MongoDB operator injection.

After sanitization, those characters are removed before they hit the database.

### Layer 7 — Rate Limiter

```js
const defaultLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,  // 15 minutes
  max: 100,                   // 100 requests per window per IP
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many requests, please try again later.' },
});

app.use(defaultLimiter);
```

If a single IP sends more than 100 requests in 15 minutes, all subsequent requests return HTTP 429.

Auth routes have a tighter limiter:

```js
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,  // only 20 attempts per 15 minutes
  ...
});
```

This protects login and registration from brute force attacks.

### Layer 8 — Socket.IO Injection

```js
if (io) {
  app.use((req, _res, next) => {
    req.io = io;
    next();
  });
}
```

In local development, the Socket.IO server is created and passed to `createApp(io)`.  This middleware attaches the Socket.IO instance to every request as `req.io`, so any controller can emit real-time events:

```js
req.io.emit('incident:new', { incident });
```

In production (Cloud Functions), `io` is `null`, so this block is skipped.

### Layer 9 — Route-level middleware

After all global middleware, Express matches the URL to a route group, then runs route-level middleware:

- `authenticate` — verifies JWT
- `authorize()` — checks role
- `validate` — checks fields

These are explained in detail below.

### Layer 10 — Controller

The actual business logic runs.

---

## 6. Route Matching

Express checks routes in the order they are mounted:

```js
app.use('/api/auth', authRoutes);
app.use('/api/applications', applicationsRoutes);
app.use('/api/inspections', inspectionsRoutes);
app.use('/api/incidents', incidentsRoutes);
app.use('/api/noc', nocRoutes);
app.use('/api/analytics', analyticsRoutes);
```

For a request to `POST /api/applications`:

1. Does it start with `/api/auth`? No.
2. Does it start with `/api/applications`? Yes → pass to `applicationsRoutes`.

Inside `applicationsRoutes`:

```js
router.use(authenticate);

router.get('/stats', authorize(ROLES.ADMIN), applicationsController.getApplicationStats);
router.get('/', applicationsController.getApplications);
router.post('/', [...validators], validate, applicationsController.createApplication);
router.get('/:id', validateObjectId('id'), applicationsController.getApplication);
...
```

`router.use(authenticate)` runs for every route in this router.

Then the method + path is matched:

- method = `POST`
- path = `/` (after stripping `/api/applications`)
- matched route = `router.post('/', ...)`

---

## 7. Authentication Middleware — JWT Flow

File: [functions/src/middleware/auth.js](functions/src/middleware/auth.js)

```js
const authenticate = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ success: false, message: 'No token provided' });
    }

    const token = authHeader.split(' ')[1];
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    const user = await User.findById(decoded.id).select('-password');
    if (!user || !user.isActive) {
      return res.status(401).json({ success: false, message: 'User not found or inactive' });
    }

    req.user = user;
    next();
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ success: false, message: 'Token expired' });
    }
    return res.status(401).json({ success: false, message: 'Invalid token' });
  }
};
```

### What happens step by step

```
Client sends:
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Step 1 — Check header exists

```js
const authHeader = req.headers.authorization;
if (!authHeader || !authHeader.startsWith('Bearer ')) {
  return res.status(401).json({ ... });
}
```

If missing or malformed → HTTP 401 immediately.

#### Step 2 — Extract token

```js
const token = authHeader.split(' ')[1];
```

The header value is `Bearer <token>`.  Split on space and take the second part.

#### Step 3 — Verify JWT

```js
const decoded = jwt.verify(token, process.env.JWT_SECRET);
```

`jwt.verify` does three things:

1. Checks the signature to confirm the token was issued by this server
2. Checks the token has not expired (`exp` claim)
3. Decodes the payload and returns it

If verification fails, an error is thrown and caught by the `catch` block.

The decoded payload looks like:

```json
{
  "id": "6623aaa111bbb222ccc333",
  "iat": 1712000000,
  "exp": 1712604800
}
```

#### Step 4 — Load user from database

```js
const user = await User.findById(decoded.id).select('-password');
```

The token's `id` is used to fetch the full user document.  The `-password` selector ensures the password hash is never attached to the request.

#### Step 5 — Check user is active

```js
if (!user || !user.isActive) {
  return res.status(401).json({ ... });
}
```

A valid token for a deactivated account is still rejected.

#### Step 6 — Attach user to request

```js
req.user = user;
next();
```

The full user object is now available to all subsequent middleware and the controller via `req.user`.

---

## 8. Authorization Middleware — RBAC

File: [functions/src/middleware/rbac.js](functions/src/middleware/rbac.js)

After authentication, authorization checks the user's role.

```js
const authorize = (...roles) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ success: false, message: 'Authentication required' });
    }
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        message: `Role '${req.user.role}' is not authorized to access this resource`,
      });
    }
    next();
  };
};
```

### Example

A route defined as:

```js
router.put('/:id/review', authorize(ROLES.ADMIN), applicationsController.reviewApplication);
```

For a user with role `applicant`:

```
req.user.role = 'applicant'
roles = ['admin']
roles.includes('applicant') → false
→ HTTP 403 returned
```

For a user with role `admin`:

```
req.user.role = 'admin'
roles.includes('admin') → true
→ next() called → controller runs
```

---

## 9. Request Validation

File: [functions/src/middleware/validator.js](functions/src/middleware/validator.js)

Validation runs before the controller to reject bad input early.

### The middleware chain on a route

```js
router.post(
  '/',
  [
    body('propertyName').trim().notEmpty().withMessage('Property name is required'),
    body('propertyType').notEmpty().withMessage('Property type is required'),
    body('address.street').notEmpty().withMessage('Street address is required'),
    body('address.city').notEmpty().withMessage('City is required'),
    body('address.state').notEmpty().withMessage('State is required'),
    body('address.zipCode').notEmpty().withMessage('ZIP code is required'),
  ],
  validate,
  applicationsController.createApplication
);
```

Each `body()` call is a middleware that checks one field.  They accumulate errors into the request object.

Then `validate` runs:

```js
const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      success: false,
      message: 'Validation failed',
      errors: errors.array().map((e) => ({ field: e.path, message: e.msg })),
    });
  }
  next();
};
```

If any field failed validation:

```json
HTTP 400
{
  "success": false,
  "message": "Validation failed",
  "errors": [
    { "field": "propertyName", "message": "Property name is required" },
    { "field": "address.city", "message": "City is required" }
  ]
}
```

If all fields pass, `next()` is called and the controller runs.

---

## 10. Controller Execution

File: [functions/src/controllers/applications.controller.js](functions/src/controllers/applications.controller.js)

After all middleware, the controller function finally runs.

### Pattern used

Every controller follows this pattern:

```js
const createApplication = async (req, res, next) => {
  try {
    // 1. Read from req.body, req.params, req.user, req.query
    // 2. Query or mutate the database
    // 3. Call services (audit, email, storage)
    // 4. Send JSON response
  } catch (error) {
    next(error);  // hand to errorHandler
  }
};
```

### Example — createApplication

```js
const createApplication = async (req, res, next) => {
  try {
    const applicationData = { ...req.body, applicant: req.user._id };
    const application = await Application.create(applicationData);

    await auditService.log({
      action: AUDIT_ACTIONS.CREATE,
      performedBy: req.user._id,
      resourceType: 'Application',
      resourceId: application._id,
      details: { applicationNumber: application.applicationNumber },
      ipAddress: req.ip,
    });

    res.status(201).json({ success: true, application });
  } catch (error) {
    next(error);
  }
};
```

What each line does:

```js
const applicationData = { ...req.body, applicant: req.user._id };
```
Merge the request body with the authenticated user's ID.  This ensures the applicant field is always the actual logged-in user, not something the client sends.

```js
const application = await Application.create(applicationData);
```
Call Mongoose's `create()` which:

1. runs Mongoose schema validation
2. triggers the pre-save hook to auto-generate `applicationNumber`
3. inserts the document into MongoDB
4. returns the saved document

```js
await auditService.log({ ... });
```
Write an immutable audit trail entry.

```js
res.status(201).json({ success: true, application });
```
Send the created document back as JSON with HTTP 201.

---

## 11. Database Interaction — MongoDB

File: [functions/src/config/db.js](functions/src/config/db.js)

### Connection

```js
const connectDB = async () => {
  try {
    const conn = await mongoose.connect(process.env.MONGODB_URI, {
      serverSelectionTimeoutMS: 5000,
    });
    logger.info(`MongoDB connected: ${conn.connection.host}`);
  } catch (error) {
    logger.error(`MongoDB connection error: ${error.message}`);
    process.exit(1);
  }
};
```

- `MONGODB_URI` is the Atlas connection string loaded from Firebase Secret Manager
- connection timeout is 5 seconds
- on failure, the process exits (Firebase will restart it)

### How models work

When a controller calls:

```js
await Application.create(data);
```

Mongoose does:

1. validates the data against the schema
2. runs any defined pre-save hooks
3. converts the document to a MongoDB-compatible BSON object
4. sends an `insertOne` command to Atlas
5. returns the inserted document

### Pre-save hook example

In [functions/src/models/Application.js](functions/src/models/Application.js):

```js
applicationSchema.pre('save', async function (next) {
  if (!this.applicationNumber) {
    const count = await mongoose.model('Application').countDocuments();
    this.applicationNumber = `NOC-${new Date().getFullYear()}-${String(count + 1).padStart(6, '0')}`;
  }
  next();
});
```

Every time an application is saved without an `applicationNumber`:

- count all existing documents
- generate a formatted number like `NOC-2026-000042`
- the hook calls `next()` to continue saving

---

## 12. Services Layer

Services are called by controllers to handle non-database side effects.

### Audit Service

File: [functions/src/services/auditService.js](functions/src/services/auditService.js)

```js
const log = async ({ action, performedBy, resourceType, resourceId, details, ipAddress, userAgent }) => {
  try {
    await AuditLog.create({
      action,
      performedBy,
      resourceType,
      resourceId,
      details,
      ipAddress,
      userAgent,
    });
  } catch (error) {
    logger.error(`Audit log error: ${error.message}`);
  }
};
```

Key design decisions:

- wrapped in try/catch so it **never crashes the caller**
- if audit logging fails, the main operation still completes
- creates a MongoDB document in the `auditlogs` collection

### Notification Service

File: [functions/src/services/notificationService.js](functions/src/services/notificationService.js)

```js
const sendApplicationStatusUpdate = async (application) => {
  if (!application.applicant || !application.applicant.email) return;

  const subject = `NOC Application ${application.applicationNumber} - Status Update`;
  const html = `
    <h2>Application Status Update</h2>
    <p>Your application <strong>${application.applicationNumber}</strong> has been updated.</p>
    <p>Current Status: <strong>${application.status.replace(/_/g, ' ').toUpperCase()}</strong></p>
    ...
  `;

  await sendEmail({ to: application.applicant.email, subject, html });
};
```

Sends transactional emails via Nodemailer using SMTP credentials from environment variables.

---

## 13. Firebase Storage In-Depth

### How files are uploaded

File: [functions/src/services/storageService.js](functions/src/services/storageService.js)

```js
const uploadFile = async (buffer, filename, contentType, folder = 'uploads') => {
  try {
    const storage = getStorage();
    const destination = `${folder}/${Date.now()}-${filename}`;
    const file = storage.file(destination);

    await file.save(buffer, { contentType, public: true });
    const [url] = await file.getSignedUrl({ action: 'read', expires: '01-01-2100' });
    return url;
  } catch (error) {
    logger.error(`File upload error: ${error.message}`);
    throw error;
  }
};
```

### Step-by-step

#### `const storage = getStorage();`

```js
const getStorage = () => admin.storage().bucket();
```

Returns the bucket configured during `initializeApp()`.  This only works because `initFirebase()` was called first when the app started.

#### `const destination = ...`

```js
const destination = `${folder}/${Date.now()}-${filename}`;
```

Example:

```
uploads/1712570000000-inspection-report.jpg
```

The timestamp prefix prevents collisions when two identical filenames are uploaded at the same time.

#### `const file = storage.file(destination);`

Creates a reference to a file at that path.  The file does not exist yet on Storage.

#### `await file.save(buffer, { contentType, public: true });`

Uploads the raw binary buffer to Cloud Storage.

- `buffer` is a `Buffer` object in memory
- `contentType` tells Storage the file type (`image/jpeg`, `application/pdf`, etc.)
- `public: true` makes the file publicly readable (required for signed URL generation)

This sends the data to Google Cloud Storage over an authenticated HTTPS connection.

#### `await file.getSignedUrl({ action: 'read', expires: '01-01-2100' });`

Generates a signed URL.

A signed URL is a special URL that:

- contains authentication information embedded in query parameters
- allows anyone with the URL to access the file
- expires on the given date (set to year 2100, effectively permanent)

Example signed URL:

```
https://storage.googleapis.com/your-project.appspot.com/uploads/1712570000000-photo.jpg
  ?X-Goog-Algorithm=GOOG4-RSA-SHA256
  &X-Goog-Credential=...
  &X-Goog-Date=20260410T000000Z
  &X-Goog-Expires=2334556800
  &X-Goog-SignedHeaders=host
  &X-Goog-Signature=...
```

This URL is what gets stored in MongoDB and returned to clients.

#### `throw error;`

Unlike the audit service, a failed upload is a hard failure.  The error propagates to the controller, which calls `next(error)`, which goes to `errorHandler`.

---

### How NOC PDFs are generated and uploaded

File: [functions/src/services/nocGenerator.js](functions/src/services/nocGenerator.js)

```js
const generatePDF = async (certificate, application) => {
  const tmpFile = await writePDF(certificate, application);

  try {
    if (process.env.FIREBASE_STORAGE_BUCKET) {
      const storage = getStorage();
      const destination = `noc-certificates/${certificate.certificateNumber}.pdf`;
      await storage.upload(tmpFile, { destination, public: true });
      const [url] = await storage.file(destination).getSignedUrl({
        action: 'read',
        expires: '01-01-2100',
      });
      fs.unlinkSync(tmpFile);
      return url;
    }
  } catch (uploadError) {
    logger.error(`PDF upload error: ${uploadError.message}`);
  } finally {
    if (fs.existsSync(tmpFile)) {
      fs.unlinkSync(tmpFile);
    }
  }

  return `/certificates/${certificate.certificateNumber}.pdf`;
};
```

### Step-by-step

1. `writePDF(certificate, application)` renders a PDF using PDFKit and writes it to `/tmp/noc-XXXX.pdf`
2. The temp file path is returned
3. `storage.upload(tmpFile, ...)` uploads the file from disk to Cloud Storage
4. A signed URL is generated
5. `fs.unlinkSync(tmpFile)` deletes the temp file to free disk space
6. The signed URL is returned, stored in the database, and returned to the client
7. If upload fails, the `finally` block still cleans up the temp file

---

## 14. Error Handling

File: [functions/src/middleware/errorHandler.js](functions/src/middleware/errorHandler.js)

When any controller calls `next(error)`, Express skips all remaining route middleware and jumps to the error handler.

```js
const errorHandler = (err, req, res, next) => {
  logger.error(err.stack || err.message);

  // Mongoose validation error
  if (err.name === 'ValidationError') {
    const errors = Object.values(err.errors).map((e) => e.message);
    return res.status(400).json({ success: false, message: 'Validation failed', errors });
  }

  // MongoDB duplicate key
  if (err.code === 11000) {
    const field = Object.keys(err.keyValue)[0];
    return res.status(409).json({
      success: false,
      message: `Duplicate value for field: ${field}`,
    });
  }

  // Mongoose CastError (bad ObjectId)
  if (err.name === 'CastError') {
    return res.status(400).json({ success: false, message: `Invalid ${err.path}: ${err.value}` });
  }

  // All other errors
  const statusCode = err.statusCode || err.status || 500;
  const message = err.message || 'Internal Server Error';
  res.status(statusCode).json({
    success: false,
    message,
    ...(process.env.NODE_ENV !== 'production' && { stack: err.stack }),
  });
};
```

### Error type mapping

| Error | Cause | HTTP Status |
|---|---|---|
| `ValidationError` | Mongoose schema validation failed | 400 |
| `code: 11000` | Duplicate unique field in MongoDB | 409 |
| `CastError` | Bad ObjectId passed | 400 |
| `TokenExpiredError` | JWT is expired | 401 |
| `statusCode` set on error | Custom errors from controllers | Varies |
| Anything else | Unexpected errors | 500 |

### 404 handler

Registered before `errorHandler`:

```js
const notFound = (req, res) => {
  res.status(404).json({ success: false, message: `Route ${req.originalUrl} not found` });
};
```

If no route matched, this runs and returns 404.

---

## 15. Response Journey

Once a controller returns a response, it travels back through the call stack:

```text
res.status(201).json({ success: true, application })
      |
      v
Express serializes the object to JSON string
      |
      v
HTTP response headers set (Content-Type: application/json, etc.)
      |
      v  
Firebase Cloud Functions runtime sends the response
      |
      v
Client receives HTTP 201 with JSON body
```

---

## 16. Cold Start vs Warm Start

Understanding this is important for Firebase Cloud Functions.

### Cold start

Happens when:

- the function has not been invoked recently
- there are no existing instances to handle the request
- Firebase needs to boot a new Node.js container

What runs:

```
require() all modules
initializeApp credentials
connectDB()
initFirebase()
createApp()
→ then handle the request
```

Cold starts take 2–5 seconds.

### Warm start

Happens when:

- an existing container is already running
- the next request goes to that container

What runs:

```
_expressApp already exists
→ skip all initialization
→ handle the request immediately
```

Warm starts take under 100 ms.

The `_expressApp` singleton in `index.js` is what enables warm start reuse:

```js
let _expressApp = null;

const getExpressApp = async () => {
  if (_expressApp) return _expressApp;  // warm start returns here
  await connectDB();
  initFirebase();
  _expressApp = createApp(null);
  return _expressApp;
};
```

---

## 17. Real-Time Events — Socket.IO

For incident reports, the backend emits real-time events so connected clients update instantly.

### How it works

In `createIncident`:

```js
req.io.emit('incident:new', { incident });
```

`req.io` is the Socket.IO server attached during app creation.

`emit('incident:new', ...)` broadcasts to all connected clients.

On the frontend:

```js
socket.on('incident:new', ({ incident }) => {
  // update the incident list in state
});
```

Clients connected to Socket.IO receive the data immediately without polling.

In Cloud Functions, `io` is null (Cloud Functions are stateless and can't maintain WebSocket connections).  Real-time would be handled by a separate long-lived service in production.

---

## 18. Full End-to-End Trace — Real Example

### Scenario: Admin reviews and approves an application

#### Request

```
PUT /api/applications/6623aaa111bbb222ccc333/review
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "status": "approved",
  "reviewNotes": "All documents verified. Premises meet fire safety standards."
}
```

#### Step 1 — Cloud Function receives request

`exports.api` in index.js runs.  `getExpressApp()` returns the cached Express app (warm start).

#### Step 2 — Global middleware runs

- **trust proxy** — sets real client IP
- **CORS** — checks origin, passes if from `FRONTEND_URL`
- **Helmet** — adds security headers to response
- **Morgan** — logs `PUT /api/applications/6623.../review`
- **Body parser** — parses JSON body into `req.body`
- **Mongo sanitize** — strips `$` and `.` from body
- **Rate limiter** — checks IP has not exceeded 100 requests in 15 min

#### Step 3 — Route matched

`/api/applications` prefix matched → `applicationsRoutes` router runs.

#### Step 4 — `router.use(authenticate)` runs

JWT extracted from Authorization header:

```
Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

`jwt.verify()` decodes payload:

```json
{ "id": "6623admin111...", "iat": 1712000000, "exp": 1712604800 }
```

User fetched from MongoDB:

```json
{ "_id": "6623admin111...", "name": "Admin User", "role": "admin", "isActive": true }
```

`req.user` is set.

#### Step 5 — `authorize(ROLES.ADMIN)` runs

```js
router.put('/:id/review', authorize(ROLES.ADMIN), ...)
```

`req.user.role` is `'admin'`.  `['admin'].includes('admin')` is true.  `next()` is called.

#### Step 6 — `validateObjectId('id')` runs

`:id` = `6623aaa111bbb222ccc333`

`mongoose.Types.ObjectId.isValid('6623aaa111bbb222ccc333')` returns true.  `next()` called.

#### Step 7 — `reviewApplication` controller runs

```js
const reviewApplication = async (req, res, next) => {
  try {
    const { status, reviewNotes, rejectionReason, assignedInspector, inspectionDate } = req.body;
    const application = await Application.findById(req.params.id).populate('applicant');

    if (!application) {
      return res.status(404).json({ success: false, message: 'Application not found' });
    }

    application.status = status;
    application.reviewNotes = reviewNotes;
    if (status === APPLICATION_STATUS.APPROVED) application.approvedAt = new Date();

    await application.save();

    await notificationService.sendApplicationStatusUpdate(application);

    await auditService.log({
      action: AUDIT_ACTIONS.APPROVE,
      performedBy: req.user._id,
      resourceType: 'Application',
      resourceId: application._id,
      details: { status, reviewNotes },
      ipAddress: req.ip,
    });

    res.json({ success: true, application });
  } catch (error) {
    next(error);
  }
};
```

What happens inside:

1. Find application by ID with applicant details populated
2. Check it exists (404 if not)
3. Update status to `approved`
4. Set `approvedAt` timestamp
5. Save to MongoDB (triggers pre-save hook if needed)
6. Send email notification to applicant
7. Write audit log entry
8. Return updated application

#### Step 8 — Email notification sent

`sendApplicationStatusUpdate` creates:

```
Subject: NOC Application NOC-2026-000042 - Status Update
To: applicant@example.com
Body: Your application NOC-2026-000042 has been updated. Status: APPROVED
```

Sent via Nodemailer SMTP.

#### Step 9 — Audit log written

MongoDB `auditlogs` collection receives a new document:

```json
{
  "action": "approve",
  "performedBy": "6623admin111...",
  "resourceType": "Application",
  "resourceId": "6623aaa111...",
  "details": { "status": "approved", "reviewNotes": "..." },
  "ipAddress": "203.0.113.45",
  "timestamp": "2026-04-10T08:30:00Z"
}
```

#### Step 10 — Response sent

```json
HTTP 200
{
  "success": true,
  "application": {
    "_id": "6623aaa111bbb222ccc333",
    "applicationNumber": "NOC-2026-000042",
    "status": "approved",
    "reviewNotes": "All documents verified...",
    "approvedAt": "2026-04-10T08:30:00.000Z",
    ...
  }
}
```

Client receives this response and can update the UI.

---

## 19. Local Development Mode

When you run `node index.js` locally:

```js
if (require.main === module) {
  require('dotenv').config();

  const http = require('http');
  const { Server } = require('socket.io');

  const server = http.createServer();
  const io = new Server(server, { cors: { ... } });

  const app = createApp(io);   // io is passed — real-time enabled
  server.on('request', app);

  io.on('connection', (socket) => {
    logger.info(`Socket connected: ${socket.id}`);
    socket.on('join:incident-room', (data) => {
      if (data?.incidentId) socket.join(`incident-${data.incidentId}`);
    });
    socket.on('disconnect', () => logger.info(`Socket disconnected: ${socket.id}`));
  });

  const startServer = async () => {
    await connectDB();
    initFirebase();
    server.listen(PORT, () => logger.info(`BLAZE dev server running on port ${PORT}`));
  };

  startServer();
}
```

Differences from production:

| Feature | Local | Production |
|---|---|---|
| Secret loading | `.env` via dotenv | Firebase Secret Manager |
| Socket.IO | Enabled (io passed to app) | Disabled (io = null) |
| HTTP server | Node.js `http.createServer()` | Firebase Cloud Functions runtime |
| Port | 5000 (or `PORT` env) | Managed by Firebase |
| Firebase credentials | Service account JSON file | Application default credentials |

---

## 20. Firebase Detailed Internals

### What Firebase Secret Manager does

When you run:

```bash
firebase functions:secrets:set MONGODB_URI
```

Firebase stores the value encrypted in Google Cloud Secret Manager.

When `exports.api` is declared with:

```js
exports.api = functions
  .runWith({ secrets: SECRET_NAMES })
  .https.onRequest(handler);
```

Before the handler runs, Firebase:

1. fetches each secret by name from Secret Manager
2. decrypts the value
3. sets it as `process.env.<NAME>` in the Node.js process
4. then calls the handler

This happens automatically — you never write this code yourself.

### What Firebase Admin SDK actually is

The `firebase-admin` npm package is a server-side SDK that acts as a trusted administrator of your Firebase project.

Comparison:

| SDK | Used in | Trust level | Can do |
|---|---|---|---|
| firebase (client) | Browser / mobile | User | Auth, Firestore reads, Storage uploads |
| firebase-admin | Server | Full admin | Create users, delete data, write anywhere |

Because the backend uses Admin SDK, it bypasses all Firebase Security Rules.  This is why proper authentication and authorization must be implemented in the Express middleware — not relying on Firebase rules.

### Firebase Storage under the hood

When you call `getStorage()`:

```js
const getStorage = () => admin.storage().bucket();
```

This returns a `Bucket` object from the `@google-cloud/storage` package (which `firebase-admin` wraps internally).

Under the hood, uploads go through:

```
Express Backend
      |
      v
@google-cloud/storage SDK
      |  (HTTPS with service account credentials)
      v
Google Cloud Storage API
      |
      v
Firebase Storage bucket (same underlying infrastructure)
      |
      v
File stored in Google Cloud
Signed URL returned
```

The signed URL allows anyone to download the file directly from Google Cloud Storage without going through your backend.

### The signed URL signing process

When you call:

```js
const [url] = await file.getSignedUrl({ action: 'read', expires: '01-01-2100' });
```

Google uses the service account's private key to create an RSA-SHA256 signature of:

```
GOOG4-RSA-SHA256
{date}
{credential_scope}
{canonical_request}
```

The signature is embedded in the URL query parameters.  When someone downloads the file using this URL:

1. Google verifies the signature
2. checks the expiry date
3. if valid, serves the file
4. no authentication required from the downloader

---

## Summary

The request flow in one line per stage:

```
Client request
  → Firebase Cloud Functions (secrets injected)
  → index.js (lazy singleton init: MongoDB + Firebase + Express)
  → app.js middleware chain (CORS → Helmet → rate limit → body parse → sanitize)
  → Route matching (which API group)
  → authenticate (JWT verified → req.user set)
  → authorize (role checked)
  → validate (input checked)
  → Controller (business logic)
  → Model (MongoDB query)
  → Service (audit / email / Firebase Storage)
  → JSON response
  → Error handler (if anything throws)
  → Client receives response
```

Every single API call follows this exact chain.
