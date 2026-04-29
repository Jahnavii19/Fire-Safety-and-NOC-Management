# 📖 BLAZE — Code Explanation

> A detailed, file-by-file guide to every piece of code in the **BLAZE** (*Building & Location Alert Zone Engine*) repository.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Repository Structure](#2-repository-structure)
3. [Frontend — `client/`](#3-frontend--client)
   - [Entry Points](#31-entry-points)
   - [Redux Store](#32-redux-store-srcappstorejs)
   - [App Routing](#33-app-routing-srcappjsx)
   - [Services](#34-services)
   - [Hooks](#35-custom-hooks)
   - [Features](#36-features)
   - [Components](#37-shared-components)
   - [Utilities](#38-utilities)
   - [Public Assets](#39-public-assets)
4. [Backend — `functions/`](#4-backend--functions)
   - [Entry Point](#41-entry-point-functionsindexjs)
   - [Express App](#42-express-app-functionssrcappjs)
   - [Config](#43-config)
   - [Models](#44-models)
   - [Controllers & Routes](#45-controllers--routes)
   - [Middleware](#46-middleware)
   - [Services](#47-backend-services)
   - [Utilities](#48-backend-utilities)
5. [Firebase Configuration](#5-firebase-configuration)
6. [CI/CD — GitHub Actions](#6-cicd--github-actions)
7. [Authentication Flow](#7-authentication-flow)
8. [Real-Time Architecture](#8-real-time-architecture)
9. [State Management](#9-state-management-redux)
10. [GitHub Pages Deployment](#10-github-pages-deployment)

---

## 1. Project Overview

**BLAZE** is a full-stack fire safety management platform. It connects three types of users:

| Role | What they do |
|------|-------------|
| **Admin** | Reviews NOC applications, assigns inspectors, issues QR certificates, views analytics |
| **Applicant** | Submits property fire-safety applications, tracks status, downloads certificates |
| **Inspector** | Receives inspection assignments, GPS check-in on-site, submits checklists and photos |

### Core Flows

```
Applicant submits application
        ↓
Admin reviews → assigns Inspector
        ↓
Inspector visits property (GPS check-in) → submits checklist
        ↓
Admin approves → QR certificate PDF generated
        ↓
Applicant downloads / Third party verifies via /verify-noc/:token
```

---

## 2. Repository Structure

```
firms/
├── .github/
│   └── workflows/
│       ├── deploy.yml          # Firebase CI/CD pipeline
│       └── github-pages.yml    # GitHub Pages deployment
│
├── client/                     # React 18 frontend (SPA)
│   ├── public/
│   │   ├── index.html          # HTML shell + SPA redirect script
│   │   ├── 404.html            # GitHub Pages SPA fallback
│   │   └── manifest.json       # PWA manifest
│   └── src/
│       ├── index.js            # React root mount
│       ├── App.jsx             # Route definitions
│       ├── index.css           # Global styles + CSS variables
│       ├── app/
│       │   └── store.js        # Redux store
│       ├── features/           # Feature-scoped modules
│       │   ├── landing/        # Public landing page
│       │   ├── auth/           # Login, Register, authSlice
│       │   ├── dashboard/      # Main dashboard
│       │   ├── applications/   # NOC application CRUD
│       │   ├── inspections/    # Inspection management
│       │   ├── incidents/      # Incident reporting & tracking
│       │   ├── noc/            # Certificate viewer & verifier
│       │   └── analytics/      # Charts & heatmaps
│       ├── components/
│       │   ├── layout/         # Sidebar, Header, PageWrapper
│       │   ├── common/         # StatusBadge, ErrorBoundary
│       │   └── maps/           # IncidentMap (Leaflet)
│       ├── services/
│       │   ├── api.js          # Axios instance with auth interceptor
│       │   ├── socket.js       # Socket.IO client singleton
│       │   └── firebase.js     # Firebase SDK initialisation
│       ├── hooks/
│       │   ├── useAuth.js      # Auth state from Redux
│       │   ├── useSocket.js    # Socket.IO connection lifecycle
│       │   └── useGeolocation.js # Browser GPS API wrapper
│       └── utils/
│           ├── constants.js    # Shared enums & default values
│           ├── formatters.js   # Date, status & text formatters
│           └── validators.js   # Input validation functions
│
├── functions/                  # Node.js 20 backend (Firebase Cloud Functions)
│   ├── index.js                # CF export + local dev server
│   └── src/
│       ├── app.js              # Express app factory
│       ├── config/
│       │   ├── db.js           # MongoDB Atlas connection
│       │   └── firebase-admin.js # Firebase Admin SDK init
│       ├── models/             # Mongoose schemas
│       ├── controllers/        # Request handlers
│       ├── routes/             # Express routers
│       ├── middleware/         # Auth, validation, error handlers
│       ├── services/           # Business logic (email, PDF, FCM)
│       └── utils/              # Logger, helpers
│
├── firestore.rules             # Firestore security rules
├── storage.rules               # Firebase Storage security rules
├── firebase.json               # Firebase project config
├── .firebaserc                 # Firebase project alias
├── README.md                   # Project overview
├── SETUP.md                    # Production deployment guide
└── CODE_EXPLANATION.md         # This file
```

---

## 3. Frontend — `client/`

### 3.1 Entry Points

#### `client/public/index.html`
The single HTML page that React mounts into. Contains:
- Standard meta tags and PWA manifest link.
- A `<script>` tag that implements the **GitHub Pages SPA redirect restore**: when GitHub Pages serves `404.html` and encodes the real URL in the query string, this script reads that query string and calls `history.replaceState()` to restore the correct URL *before* React mounts, so React Router sees the right path.

#### `client/public/404.html`
A minimal HTML page that GitHub Pages serves when a sub-route (e.g. `/firms/dashboard`) is requested directly. It encodes the full requested path into the query string and redirects to `index.html`. This is the standard trick to make Single-Page Apps work on GitHub Pages.

#### `client/public/manifest.json`
The [Web App Manifest](https://developer.mozilla.org/en-US/docs/Web/Manifest). Enables the app to be installed as a Progressive Web App (PWA). Defines the short name (`BLAZE`), full name, theme colour, and background colour.

#### `client/src/index.js`
The React entry point. Renders `<App />` inside:
- `<React.StrictMode>` — extra development-time warnings.
- `<Provider store={store}>` — makes the Redux store available to all components.
- `<BrowserRouter>` — enables React Router with real URL paths.
- `<ToastContainer>` — global toast notification container (react-toastify).

---

### 3.2 Redux Store (`src/app/store.js`)

Configures the Redux store using `@reduxjs/toolkit`'s `configureStore`. Registers:

| Slice / API | Purpose |
|---|---|
| `auth` | User session: token, user object, loading state |
| `applicationsApi` | RTK Query API slice for NOC applications |
| `incidentsApi` | RTK Query API slice for fire incidents |
| `nocApi` | RTK Query API slice for certificates |
| `inspectionsApi` | RTK Query API slice for inspections |

RTK Query middleware is appended to `getDefaultMiddleware()` so that caching, cache invalidation, and background re-fetching work correctly.

---

### 3.3 App Routing (`src/App.jsx`)

Defines the application's route tree using React Router v6.

#### Route types

| Wrapper | Behaviour |
|---|---|
| `<LandingPage />` | Public — always accessible at `/`, no auth required |
| `<PublicRoute>` | Redirects logged-in users to `/dashboard` |
| `<ProtectedRoute>` | Redirects unauthenticated users to `/login`; wraps content in `<PageWrapper>` |

#### `LoadingScreen`
Shown while the app is checking whether a stored JWT is still valid (`fetchMe` async thunk is in-flight). Prevents a flash of the login page for already-authenticated users.

#### `NotFound`
Simple 404 fallback rendered for any unrecognised URL.

On mount, if a JWT is stored in `localStorage` under the key `blaze_token`, the app dispatches `fetchMe()` to validate the token with the backend and hydrate the user object in Redux.

---

### 3.4 Services

#### `src/services/api.js`
A singleton **Axios** instance.

- `baseURL` is set from `REACT_APP_API_URL` (defaults to `/api`, which is proxied to `localhost:5000` during local development).
- **Request interceptor** — reads `blaze_token` from `localStorage` and attaches it as `Authorization: Bearer <token>` on every request.
- **Response interceptor** — if the server responds with `401 Unauthorized`, clears the token and redirects to `/login`.

#### `src/services/socket.js`
A singleton **Socket.IO** client.

- `getSocket()` — lazily creates the socket instance (does not auto-connect).
- `connectSocket(token)` — attaches the JWT as `socket.auth.token` (the backend verifies this on handshake) and connects.
- `disconnectSocket()` — gracefully disconnects.

The lazy-singleton pattern ensures only one WebSocket connection exists for the entire app lifetime.

#### `src/services/firebase.js`
Initialises the **Firebase SDK** using `REACT_APP_FIREBASE_*` environment variables. Exports:
- `auth` — Firebase Authentication instance.
- `storage` — Firebase Storage instance (used for photo uploads in inspections).
- `messaging` — Firebase Cloud Messaging instance (push notifications).

---

### 3.5 Custom Hooks

#### `src/hooks/useAuth.js`
Reads auth state from the Redux store using `useSelector` and returns a convenient object:

```js
{
  user, token, loading, error, initialized,
  isAuthenticated,   // true when user + token both exist
  isAdmin,           // user.role === 'admin'
  isInspector,       // user.role === 'inspector'
  isApplicant,       // user.role === 'applicant'
  logout,            // dispatches the logout action (clears Redux + localStorage)
  refreshUser,       // re-fetches the current user from the backend
}
```

Used throughout the app instead of calling `useSelector` directly to avoid boilerplate.

#### `src/hooks/useSocket.js`
Manages the Socket.IO connection lifecycle for a component:

1. When a valid `token` is in Redux, calls `connectSocket(token)`.
2. Listens to `connect` / `disconnect` events to track `isConnected`.
3. Exposes stable `on`, `off`, `emit` callbacks (wrapped in `useCallback`) that components can safely use in `useEffect` dependency arrays without causing infinite loops.
4. On unmount (or when the token disappears), calls `disconnectSocket()`.

#### `src/hooks/useGeolocation.js`
Wraps the browser `navigator.geolocation` API:
- Calls `getCurrentPosition` on mount.
- Returns `{ location: { lat, lng, accuracy }, error, loading, refresh }`.
- Uses `useCallback` to make `refresh` stable across renders.
- Configured for high-accuracy GPS (`enableHighAccuracy: true`).

Used by `InspectionList` to enable GPS-based check-in.

---

### 3.6 Features

#### `src/features/landing/LandingPage.jsx`
The **public landing page** — always accessible at `/` without logging in.

Sections:
1. **Navbar** — sticky navigation with links to page sections and a "Sign In" CTA.
2. **Hero** — headline, description, primary & ghost CTAs, and a mock dashboard card that previews the UI.
3. **Stats strip** — animated counters (Applications, Uptime, Roles, APIs) that count up when scrolled into view using `IntersectionObserver`.
4. **Features** — six feature cards with coloured icon wrappers and accent bars.
5. **How it works** — three-step workflow (Submit → Inspect → Certificate).
6. **Roles** — three role cards (Admin, Applicant, Inspector) with capability lists.
7. **Tech stack** — pill badges for every technology used.
8. **CTA banner** — secondary call-to-action with gradient background.
9. **Footer** — brand mark (🔥 BLAZE), project tagline, and copyright notice.

The `useCounter` hook internally uses `IntersectionObserver` to trigger the count-up animation only when the stat element scrolls into view.

---

#### `src/features/auth/authSlice.js`
Redux slice for authentication. Uses `createSlice` and `createAsyncThunk`.

**Async thunks:**

| Thunk | HTTP call | On success |
|---|---|---|
| `login` | `POST /auth/login` | Saves token to localStorage, sets user in state |
| `register` | `POST /auth/register` | Same as login |
| `fetchMe` | `GET /auth/me` | Hydrates `user` from stored token (used on app init) |

**Sync actions:**
- `logout` — clears `user`, `token`, and removes `blaze_token` from localStorage.
- `clearError` — resets the `error` field (called before each login attempt).
- `setInitialized` — marks auth as initialized without other state changes.

**State shape:**
```js
{
  user: null | { _id, name, email, role, organization, phone },
  token: null | string,
  loading: boolean,
  error: null | string,
  initialized: boolean,  // true once the initial fetchMe resolves
}
```

---

#### `src/features/auth/LoginPage.jsx`
Login form component.
- Controlled form with `email` and `password` fields.
- Dispatches `login(formData)` on submit.
- On success: shows a toast and navigates to `/dashboard`.
- On failure: shows an error toast.
- All styles are inline (inline-style pattern used throughout the app).

#### `src/features/auth/RegisterPage.jsx`
Registration form. Same pattern as LoginPage but collects `name`, `email`, `password`, `phone`, `organization`, and `role`. Role is limited to `applicant` or `inspector` (admins are created out-of-band).

---

#### `src/features/dashboard/DashboardPage.jsx`
The main dashboard for logged-in users.

- **Admin** users see four stat cards: Total Applications, Pending Review, Approved/Certified, Active Incidents — powered by RTK Query (`useGetApplicationStatsQuery`, `useGetIncidentStatsQuery`). The raw API response returns per-status counts, which the component derives into aggregate values (e.g. pending = submitted + under_review).
- **Applicants** see their own application count, pending count, and approved count — computed from `useGetApplicationsQuery`.
- **Inspectors** see their assigned inspection count — computed from `useGetInspectionsQuery`.
- **All users** see the live incident map (`<IncidentMap />`).
- **Quick Actions** links row for common navigation shortcuts.
- `StatCard` — a reusable card linking to the relevant page.

---

#### `src/features/applications/`

| File | Purpose |
|---|---|
| `applicationsApi.js` | RTK Query API slice. Defines `getApplications`, `getApplication`, `createApplication`, `updateApplication`, `submitApplication`, `reviewApplication`, `getApplicationStats` endpoints. |
| `ApplicationList.jsx` | Paginated table of NOC applications with status badges. Reads `?status=` from the URL query string for pre-filtering. |
| `ApplicationForm.jsx` | Multi-field form to create or edit a NOC application (property details, type, address, etc.). |
| `ApplicationDetail.jsx` | Full detail view of one application. Admins can change the status; applicants can see the current state and any attached inspection. |

---

#### `src/features/incidents/`

| File | Purpose |
|---|---|
| `incidentsApi.js` | RTK Query slice. Endpoints: `getIncidents`, `getIncident`, `createIncident`, `updateIncident`, `addIncidentUpdate`, `getIncidentStats`. |
| `IncidentTable.jsx` | Table of incidents with inline "Report Incident" form. Severity is colour-coded. Listens on `incident:new` Socket.IO event and calls `refetch()` to refresh the list in real time. |
| `IncidentDetail.jsx` | Detail view showing all incident updates timeline, location, severity, status controls. |

---

#### `src/features/inspections/`

| File | Purpose |
|---|---|
| `inspectionsApi.js` | RTK Query slice. Endpoints: `getInspections`, `getInspection`, `createInspection`, `updateInspection`, `checkIn`, `submitChecklist`. |
| `InspectionList.jsx` | Table of assigned inspections. Shows current GPS coordinates (from `useGeolocation`). Inspectors can press "Check-in" to POST their GPS coordinates to the backend for that inspection. |
| `InspectionDetail.jsx` | Detail page for a single inspection. Shows inspection status, scheduled date, result and score, property details, inspector info with GPS check-in coordinates. Displays the full checklist with pass/fail indicators, uploaded photos in a grid, and inspector notes. |

---

#### `src/features/noc/`

| File | Purpose |
|---|---|
| `nocApi.js` | RTK Query slice. Endpoints: `getCertificates`, `getCertificate`, `issueCertificate`, `revokeCertificate`, `verifyCertificate`. |
| `NOCViewer.jsx` | Card grid of issued NOC certificates. Each card shows validity dates, property name, status badge, and buttons to view details or download the PDF. |
| `NOCDetail.jsx` | Detail page for a single certificate. Shows a validity banner (green for valid, red for expired/revoked), certificate number, status, issue and expiry dates, property details, QR code, public verification link, PDF download button, and an admin revoke action. |
| `VerifyNOC.jsx` | Public verification page at `/verify-noc/:token`. No auth required. Calls `verifyCertificate(token)` and shows a full certificate summary with a valid/invalid indicator. Used by third parties to verify a certificate's authenticity. |

---

#### `src/features/analytics/`

| File | Purpose |
|---|---|
| `AnalyticsDashboard.jsx` | Fetches three backend analytics endpoints in parallel (`/analytics/dashboard`, `/analytics/trends/applications`, `/analytics/metrics/inspections`). Renders a stat row, a Recharts line chart (application trend), and a Recharts pie chart (inspection results). |
| `Heatmap.jsx` | Renders a Leaflet-based heatmap of incident locations using the `leaflet.heat` plugin. Fetches all active incidents and maps them to `[lat, lng, intensity]` triplets. |

---

### 3.7 Shared Components

#### `src/components/layout/PageWrapper/PageWrapper.jsx`
Renders the standard app shell: `<Sidebar />` on the left, `<Header />` at the top, and the page `children` in the main content area. Applied by `ProtectedRoute` to all authenticated pages.

**Responsive Layout Logic**:
This component manages the mobile navigation state. It detects screen size and provides a `sidebar-overlay` and toggle functionality for the mobile drawer.

CSS classes (`app-layout`, `main-content`, `page-wrapper`) are defined in `index.css`.

#### `src/components/layout/Sidebar/Sidebar.jsx`
Fixed left navigation. Features:
- BLAZE logo and tagline.
- Navigation links filtered by the current user's `role` (only shows links the user has access to).
- User avatar (initial letter), name, and role at the bottom.
- "Sign Out" button that dispatches `logout()` and navigates to `/login`.

`NAV_ITEMS` array drives the menu — each item declares which roles can see it via a `roles` array.

#### `src/components/layout/Header/Header.jsx`
Sticky top bar. Shows:
- The current page title (looked up from a `PAGE_TITLES` map keyed by pathname).
- The user's organisation name (or their own name) and role badge.

#### `src/components/common/StatusBadge/StatusBadge.jsx`
A small coloured pill that renders a human-readable label for any status string (e.g. `under_review` → "Under Review" with a yellow background). `STATUS_CONFIG` maps every known status to `{ label, bg, color }`. Falls back gracefully to the raw status string with a grey background for unknown values.

#### `src/components/common/ErrorBoundary.jsx`
A React class component that implements `componentDidCatch`. Wraps the entire app in `App.jsx`. If any descendant throws an unhandled error during rendering, the error boundary catches it and renders a fallback UI instead of crashing the whole page.

#### `src/components/maps/IncidentMap/IncidentMap.jsx`
An interactive Leaflet map rendered via `react-leaflet`.

- Centred on India (`[20.5937, 78.9629]`) at zoom level 5.
- Fetches active incidents from `incidentsApi`.
- For each incident, renders:
  - A custom `divIcon` dot coloured by severity.
  - A translucent `<Circle>` whose radius scales with severity (critical = 8 km radius, low = 1.5 km).
  - A `<Popup>` with title, severity, status, type, and city.
- Listens to `incident:new` and `incident:updated` Socket.IO events and updates the marker list in real time without a full re-fetch.

The default Leaflet icon URLs are patched (the `delete L.Icon.Default.prototype._getIconUrl` pattern) to work correctly when the app is bundled by webpack.

---

### 3.8 Utilities

#### `src/utils/constants.js`
Shared enumeration constants:

| Constant | Values |
|---|---|
| `ROLES` | `admin`, `applicant`, `inspector` |
| `INCIDENT_SEVERITIES` | `low`, `medium`, `high`, `critical` |
| `INCIDENT_TYPES` | `fire`, `explosion`, `chemical_leak`, `structural`, `other` |
| `PROPERTY_TYPES` | `residential`, `commercial`, `industrial`, `educational`, `healthcare`, `other` |
| `APPLICATION_STATUSES` | Full pipeline from `draft` to `certificate_issued` |
| `DEFAULT_MAP_CENTER` | `[20.5937, 78.9629]` (centre of India) |
| `DEFAULT_MAP_ZOOM` | `5` |

#### `src/utils/formatters.js`
Pure formatting functions (no side effects):

| Function | What it does |
|---|---|
| `formatDate(date)` | Formats a date as `dd Mon yyyy` using `en-IN` locale |
| `formatDateTime(date)` | Same but includes time |
| `capitalize(str)` | Capitalises the first letter |
| `formatStatus(status)` | Converts `under_review` → `Under Review` |
| `truncate(str, maxLength)` | Truncates to `maxLength` characters and appends `...` |

#### `src/utils/validators.js`
Pure validation functions (return `true`/`false`):

| Function | Rule |
|---|---|
| `isValidEmail(email)` | Standard email regex |
| `isValidPhone(phone)` | 10–15 digits, allows `+`, spaces, hyphens |
| `isValidPassword(password)` | At least 8 characters |
| `isValidCoordinate(lat, lng)` | lat ∈ [-90, 90], lng ∈ [-180, 180] |

---

### 3.9 Public Assets

#### `client/public/manifest.json`
PWA manifest. Allows users to "Add to Home Screen" on mobile. Sets:
- `short_name`: `BLAZE`
- `name`: `BLAZE — Building & Location Alert Zone Engine`
- `theme_color`: `#e55c4a` (BLAZE primary red)
- `background_color`: `#1a1a2e` (deep navy)
- `display`: `standalone` (looks like a native app, no browser chrome)

---

## 4. Backend — `functions/`

### 4.1 Entry Point (`functions/index.js`)
Has two execution modes:

**Production (Firebase Cloud Function):**
- Exports `api` as a Firebase HTTPS Cloud Function via `functions.runWith({ secrets: SECRET_NAMES }).https.onRequest(...)`.
- `SECRET_NAMES` lists every secret to inject from **Firebase Secret Manager** at runtime.
- The Express app is created lazily (`getExpressApp`) and reused across warm invocations (cold-start optimisation).
- Socket.IO is passed as `null` in Cloud Function mode because CF instances are stateless HTTP — real-time requires a separate long-lived service (Cloud Run).

**Local development (direct `node index.js`):**
- `require('dotenv').config()` loads `functions/.env`.
- Creates an `http.Server`, attaches `Socket.IO` to it with CORS configured from `FRONTEND_URL`.
- Calls `connectDB()` and `initFirebase()` then listens on `PORT` (default 5000).
- Handles `join:incident-room` socket events so clients can subscribe to per-incident update streams.

---

### 4.2 Express App (`functions/src/app.js`)
A factory function `createApp(io)` that:
1. Creates an Express instance.
2. Applies global middleware: `cors`, `helmet`, `express.json`, `morgan` logging.
3. Attaches `io` (Socket.IO server) to `req.io` via a middleware so any controller can emit events.
4. Mounts all routers under `/api/` prefix.
5. Registers the global error handler as the last middleware.

---

### 4.3 Config

#### `functions/src/config/db.js`
Connects to **MongoDB Atlas** using `mongoose.connect(process.env.MONGODB_URI)`. Caches the connection so repeated calls in warm Cloud Function invocations don't open new connections.

#### `functions/src/config/firebase-admin.js`
Initialises the **Firebase Admin SDK** with the service account credentials provided via `FIREBASE_PROJECT_ID`. Used by backend services for:
- Uploading PDFs/photos to Firebase Storage.
- Sending push notifications via Firebase Cloud Messaging (FCM).
- Verifying Firebase Auth tokens (if used).

---

### 4.4 Models

Mongoose schemas define the MongoDB document shapes and validation rules.

| Model | Key Fields |
|---|---|
| `User` | `name`, `email` (unique), `password` (hashed), `role`, `organization`, `phone`, `fcmToken` |
| `Application` | `applicationNumber` (auto-gen), `applicant` (ref User), `propertyName`, `propertyType`, `propertyDetails`, `status`, pipeline timestamps |
| `Inspection` | `application` (ref), `inspector` (ref User), `scheduledDate`, `checklist[]`, `photos[]`, `gpsCheckIn`, `overallResult`, `status` |
| `Incident` | `incidentNumber` (auto-gen), `title`, `type`, `severity`, `location.coordinates { lat, lng }`, `status`, `updates[]` |
| `NOCCertificate` | `certificateNumber`, `application` (ref), `verificationToken` (UUID), `qrCodeUrl`, `pdfUrl`, `validFrom`, `validUntil`, `status` |
| `AuditLog` | `action`, `performedBy` (ref User), `targetType`, `targetId`, `details`, `ipAddress`, `timestamp` |

---

### 4.5 Controllers & Routes

Each feature domain has a controller (business logic) and a router (HTTP method + path binding).

| Route prefix | Controller | Responsibility |
|---|---|---|
| `POST /api/auth/login` | `authController` | Validate credentials, issue JWT |
| `POST /api/auth/register` | `authController` | Hash password, create User, issue JWT |
| `GET /api/auth/me` | `authController` | Return the authenticated user from token |
| `GET /api/applications` | `applicationsController` | List applications (paginated, filtered by role) |
| `POST /api/applications` | `applicationsController` | Create draft application |
| `PUT /api/applications/:id/review` | `applicationsController` | Admin changes status + assigns inspector |
| `GET /api/incidents` | `incidentsController` | List incidents (paginated) |
| `POST /api/incidents` | `incidentsController` | Report new incident; emits `incident:new` via Socket.IO |
| `PUT /api/incidents/:id` | `incidentsController` | Update incident; emits `incident:updated` |
| `GET /api/inspections` | `inspectionsController` | List (scoped: inspector sees only assigned) |
| `POST /api/inspections/:id/checkin` | `inspectionsController` | Validate GPS coordinates and record check-in |
| `POST /api/noc/issue/:appId` | `nocController` | Generate QR code + PDF, store in Firebase Storage |
| `GET /api/noc/verify/:token` | `nocController` | Public — no auth — verify certificate by token |
| `GET /api/analytics/dashboard` | `analyticsController` | Aggregate counts for the admin stats row |

---

### 4.6 Middleware

#### `authenticate`
Express middleware that reads the `Authorization: Bearer <token>` header, verifies the JWT with `jsonwebtoken`, and attaches `req.user` for downstream controllers. Returns `401` if the token is missing, expired, or invalid.

#### `authorize(...roles)`
Middleware factory. Called as `authorize('admin')` or `authorize('admin', 'inspector')`. Checks `req.user.role` and returns `403 Forbidden` if the role is not in the allowed list.

#### `validate(schema)`
Middleware factory using **express-validator**. Each route defines its own validation chains (e.g. `body('email').isEmail()`), and `validate` is the result-checker middleware that collects validation errors and returns `400 Bad Request` with field-level error messages if any fail.

#### `errorHandler`
Global error-handling middleware (4 arguments). Catches anything passed to `next(err)`. Logs the error and returns a JSON error response with an appropriate HTTP status code.

---

### 4.7 Backend Services

#### `notificationService.js`
Sends transactional emails using **Nodemailer** with Gmail SMTP (`EMAIL_HOST`, `EMAIL_USER`, `EMAIL_PASS`). Used for:
- Application status change notifications.
- Certificate issued notification with PDF attachment.
- Inspection assignment and completion alerts.

#### `nocGenerator.js`
Generates the NOC certificate PDF using **PDFKit**. Embeds:
- QR code image (generated with the `qrcode` library, pointing to `/verify-noc/:token`).
- Property details, validity dates, certificate number.
- Uploads the PDF to Firebase Storage via `storageService` and returns the download URL.

#### `storageService.js`
Firebase Storage helper. Handles file uploads to Cloud Storage buckets and returns public/signed URLs. Used by `nocGenerator` for PDF uploads and by inspection controllers for photo uploads.

#### `auditService.js`
Writes immutable `AuditLog` entries to MongoDB for every significant action (application reviews, certificate issuance, revocations). Wrapped in try/catch so it **never throws** — audit failures do not block the primary operation.

---

### 4.8 Backend Utilities

#### `functions/src/utils/logger.js`
A Winston logger configured with `console` transport for Cloud Functions (structured JSON in production, colourised text in development).

---

## 5. Firebase Configuration

### `firebase.json`
Tells the Firebase CLI how to deploy:
- `hosting.public`: `client/build` — serve the built React app from Firebase Hosting.
- `hosting.rewrites`: all routes (`**`) serve `index.html` — enables SPA routing on Firebase Hosting.
- `functions.source`: `functions` — deploy the Node.js code from the `functions/` directory.

### `.firebaserc`
Maps the project alias `default` to the Firebase project ID (e.g. `blaze-fire-safety`).

### `firestore.rules`
Security rules for Cloud Firestore (if used). Typically locks down all reads/writes by default and only opens up specific collections with auth checks.

### `storage.rules`
Security rules for Firebase Storage. Allows authenticated users to upload to their own paths (e.g. `inspections/{userId}/...`) and restricts public access to certificate PDFs only.

---

## 6. CI/CD — GitHub Actions

### `.github/workflows/deploy.yml` — BLAZE CI/CD Pipeline

Runs on every `push` or `pull_request` to `main`.

**Job 1: `test-backend`**
- Runs in `./functions`
- `npm ci` → `npm test`
- Needs `JWT_SECRET` and `MONGODB_URI_TEST` secrets.

**Job 2: `test-frontend`**
- Runs in `./client`
- `npm ci` → `npm test` (with `CI=true` so warnings = errors)
- `npm run build` (with `CI=false` + all `REACT_APP_*` secrets baked in)

**Job 3: `deploy`** *(push to main only)*
- Depends on both test jobs passing.
- Rebuilds the frontend bundle with production secrets.
- Deploys to **Firebase Hosting + Functions** using the `w9jds/firebase-action` action and `FIREBASE_TOKEN` secret.

### `.github/workflows/github-pages.yml` — GitHub Pages Deployment

Runs on `push` to `main` or manually via `workflow_dispatch`.

Steps:
1. Checkout code.
2. `npm ci` in `./client`.
3. `npm run build` with `PUBLIC_URL=/firms` so all asset paths are relative to the repo sub-path.
4. `actions/configure-pages` — sets up Pages environment.
5. `actions/upload-pages-artifact` — uploads `client/build/` as the Pages artifact.
6. `actions/deploy-pages` — publishes the artifact to `https://bnaveen07.github.io/firms`.

---

## 7. Authentication Flow

```
User submits login form
        ↓
authSlice.login thunk → POST /api/auth/login
        ↓ (backend)
  Validate email + bcrypt.compare(password, hash)
  Sign JWT: { userId, role, exp }
        ↓
Return { token, user }
        ↓ (frontend)
  localStorage.setItem('blaze_token', token)
  Redux state: { user, token, initialized: true }
        ↓
App.jsx useEffect → dispatch(fetchMe()) [on every refresh]
  GET /api/auth/me with Bearer token
  → Hydrates user object in Redux
```

**On logout:**
- Redux `logout` action clears `user` and `token`.
- `localStorage.removeItem('blaze_token')`.
- React Router navigates to `/login`.

**Token expiry:**
- The `api.js` response interceptor catches `401` responses and performs the same logout + redirect automatically.

---

## 8. Real-Time Architecture

BLAZE uses **Socket.IO** for real-time incident updates.

```
Browser (useSocket hook)          Backend (Socket.IO server)
        │                                    │
        │── connect (auth: { token }) ──────►│
        │◄── connected ──────────────────────│
        │                                    │
        │── join:incident-room ─────────────►│  (joins room `incident-{id}`)
        │                                    │
        │     [Another user reports incident]│
        │                                    │── incidentsController.create()
        │                                    │   req.io.emit('incident:new', incident)
        │◄── incident:new ────────────────────│
        │                                    │
  IncidentTable.jsx                          │
  calls refetch()                            │
```

**`useSocket` hook lifecycle:**
1. When Redux `token` becomes truthy → `connectSocket(token)`.
2. Component calls `on(event, handler)` to subscribe.
3. Component's `useEffect` cleanup calls `off(event, handler)` to unsubscribe.
4. On unmount or logout → `disconnectSocket()`.

The `on` and `off` callbacks are wrapped in `useCallback` so they are stable references — safe to include in `useEffect` dependency arrays.

---

### 9. State Management (Redux) & Styling

BLAZE uses **Redux Toolkit** with two complementary approaches, and a standardized CSS system for styling:

#### Centralized Design System (`index.css`)
To ensure consistency and responsiveness, the app uses a utility-first CSS approach for core components:
- `.blaze-btn` / `.blaze-btn-primary`: Standardized buttons with hover states.
- `.blaze-input`: Uniform form inputs with focus indicators.
- `.blaze-badge`: Styled status indicators.
- `.blaze-card-interactive`: Hover animations for dashboard and landing cards.
- **Responsive Utilities**: Classes like `.hero-responsive` and `.register-form-grid` handle viewport-specific layouts.

### Redux Slice (`auth`)
For authentication state that is global, complex, and requires async logic (`createAsyncThunk`). State is manually managed with `extraReducers`.

### RTK Query (`applicationsApi`, `incidentsApi`, `nocApi`, `inspectionsApi`)
For server state (API data). RTK Query handles:
- **Caching** — data is stored in Redux and reused until invalidated.
- **Deduplication** — if two components mount at the same time and both request the same query, only one HTTP request is made.
- **Cache invalidation** — mutations declare which `tagTypes` they invalidate, causing the affected queries to automatically re-fetch.
- **Loading / error states** — exposed as `isLoading`, `isError`, `data` from the query hook.

Example tag flow:
```
useGetApplicationsQuery() → providesTags: ['Application']
createApplicationMutation → invalidatesTags: ['Application']
→ RTK Query auto re-fetches the list after a new application is created
```

---

## 10. GitHub Pages Deployment

### Why `PUBLIC_URL=/firms`?
GitHub Pages hosts the app at `https://bnaveen07.github.io/firms` (note the `/firms` sub-path). React's build system uses `PUBLIC_URL` to prefix all asset links (`/firms/static/js/main.js`, `/firms/static/css/main.css`). Without this, assets load from the root domain and the page is blank.

### Why `404.html`?
GitHub Pages is a static file host. When a user navigates directly to `https://bnaveen07.github.io/firms/dashboard`, GitHub looks for a file at `firms/dashboard/index.html` — which doesn't exist — and serves `404.html` instead. The `404.html` encodes the URL and redirects to `index.html`, where the redirect-restore script in the `<head>` fixes the History entry before React mounts.

### `homepage` in `package.json`
```json
"homepage": "https://bnaveen07.github.io/firms"
```
React CRA uses this to compute `PUBLIC_URL` when you run `npm run build`. It also affects the `start_url` in the manifest.

### Manual deploy
```bash
cd client
npm run deploy   # → npm run build then gh-pages -d build
```
`gh-pages` pushes the `build/` directory to the `gh-pages` branch. GitHub Pages serves from that branch.

---

*This document was generated as part of the BLAZE project. Keep it up to date whenever adding new features or files.*
