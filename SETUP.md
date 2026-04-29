# BLAZE — Production Setup Guide

**Building & Location Alert Zone Engine (BLAZE)**

> **This guide covers production deployment only.**  
> All secrets are managed through **GitHub Secrets** (for CI/CD and frontend build) and **Firebase Secret Manager** (for backend runtime). No `.env` files exist in the production environment — they are used only for local development.

---

## Table of Contents
1. [How Secrets Work in BLAZE](#1-how-secrets-work-in-blaze)
2. [Prerequisites & Accounts](#2-prerequisites--accounts)
3. [Project Structure](#3-project-structure)
4. [Firebase Project Setup](#4-firebase-project-setup)
5. [MongoDB Atlas Production Setup](#5-mongodb-atlas-production-setup)
6. [Gmail SMTP App Password](#6-gmail-smtp-app-password)
7. [GitHub Secrets — Complete List](#7-github-secrets--complete-list)
8. [Firebase Secret Manager — Complete List](#8-firebase-secret-manager--complete-list)
9. [Production Build & Deploy](#9-production-build--deploy)
10. [Create the First Admin Account](#10-create-the-first-admin-account)
11. [Post-Deployment Verification](#11-post-deployment-verification)
12. [API Reference](#12-api-reference)
13. [Production Security Checklist](#13-production-security-checklist)
14. [Monitoring & Observability](#14-monitoring--observability)
15. [Troubleshooting](#15-troubleshooting)
16. [Local Development](#16-local-development)

---

## 1. How Secrets Work in BLAZE

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SECRET FLOW DIAGRAM                                 │
│                                                                             │
│  Developer  ──────► GitHub Secrets ─────────────────────────────────────┐  │
│                       (repo Settings)        │ injected as env vars      │  │
│                                              │ during GitHub Actions     │  │
│                                              ▼                           │  │
│                                    ┌──────────────────┐                  │  │
│                                    │  CI/CD Pipeline  │                  │  │
│                                    │  (deploy.yml)    │                  │  │
│                                    └────────┬─────────┘                  │  │
│                                             │                            │  │
│                           ┌─────────────────┴─────────────────┐         │  │
│                           ▼                                   ▼         │  │
│                  ┌─────────────────┐                ┌─────────────────┐  │  │
│                  │  React Build    │                │  Firebase       │  │  │
│                  │  (static files) │                │  Functions      │  │  │
│                  │  REACT_APP_*    │                │  deploy cmd     │  │  │
│                  │  baked in at    │                └────────┬────────┘  │  │
│                  │  build time     │                         │           │  │
│                  └────────┬────────┘                         │           │  │
│                           │                                  │           │  │
│                           ▼                                  ▼           │  │
│                  Firebase Hosting                 Firebase Cloud Function │  │
│                  (CDN — public)                   reads secrets via       │  │
│                                                   process.env.*          │  │
│                                                            ▲             │  │
│                                                            │             │  │
│  Developer  ──► Firebase Secret Manager ──────────────────┘             │  │
│                  (firebase functions:secrets:set)                        │  │
│                  MONGODB_URI, JWT_SECRET, etc.                           │  │
└─────────────────────────────────────────────────────────────────────────────┘
```

| Secret Store | What it holds | Who/what reads it |
|---|---|---|
| **GitHub Secrets** | `REACT_APP_*` Firebase config, `FIREBASE_TOKEN`, test vars | GitHub Actions workflow at CI/CD time |
| **Firebase Secret Manager** | `MONGODB_URI`, `JWT_SECRET`, `EMAIL_*`, `FRONTEND_URL`, etc. | Firebase Cloud Function at request runtime |

**Nothing is ever stored in a `.env` file in production. No secrets appear in source code or workflow YAML as plain text.**

---

## 2. Prerequisites & Accounts

### 2.1 Software

| Tool | Version | How to Get |
|------|---------|-----------|
| Node.js | 20.x LTS | https://nodejs.org — choose "LTS" |
| npm | 10.x (included) | Comes with Node.js |
| Git | Latest | https://git-scm.com/downloads |
| Firebase CLI | Latest | `npm install -g firebase-tools` |

```bash
# Verify after installing
node --version      # Must show v20.x.x
npm --version       # Must show 10.x.x
firebase --version
```

### 2.2 Service Accounts Required

| Service | URL | Purpose |
|---------|-----|---------|
| Firebase (Google) | https://console.firebase.google.com | Hosting, Cloud Functions, Storage, FCM |
| MongoDB Atlas | https://cloud.mongodb.com | Managed MongoDB database |
| GitHub | https://github.com | Source control + Secrets store for CI/CD |
| Google Account | https://accounts.google.com | Gmail SMTP for email notifications |

---

## 3. Project Structure

```
firms/
├── client/                        # React 18 SPA → Firebase Hosting
│   ├── public/
│   │   ├── index.html             # Leaflet CSS linked here
│   │   ├── manifest.json          # PWA manifest
│   │   └── firebase-messaging-sw.js  # FCM background service worker
│   └── src/
│       ├── app/store.js           # Redux store (all slices + RTK Query APIs)
│       ├── features/
│       │   ├── auth/              # Login, Register + authSlice (JWT in localStorage)
│       │   ├── dashboard/         # Stat cards + live Leaflet incident map
│       │   ├── applications/      # NOC workflow: list / form / detail
│       │   ├── inspections/       # Inspector list, GPS check-in, checklists
│       │   ├── incidents/         # Live incident table + detail view
│       │   ├── noc/               # NOC certificate viewer + public QR verify page
│       │   └── analytics/         # Charts, heatmap, risk score
│       ├── components/
│       │   ├── common/ErrorBoundary.jsx   # Catches React render errors
│       │   ├── common/StatusBadge/        # Coloured status pill
│       │   ├── layout/Sidebar/            # Role-aware nav sidebar
│       │   ├── layout/Header/             # Top bar + user menu + logout
│       │   ├── layout/PageWrapper/        # Wraps all protected pages
│       │   └── maps/IncidentMap/          # Leaflet map; reacts to Socket.IO events
│       ├── hooks/
│       │   ├── useAuth.js         # Reads Redux auth state (isAuthenticated, isAdmin, user, token)
│       │   ├── useSocket.js       # Socket.IO connection; memoised on/off/emit with useCallback
│       │   └── useGeolocation.js  # Browser Geolocation API; used by inspector GPS check-in
│       └── services/
│           ├── api.js             # Axios instance; auto-injects Authorization header
│           ├── firebase.js        # Firebase JS SDK init (Storage + Messaging)
│           └── socket.js          # Socket.IO singleton factory
│
├── functions/                     # Node.js 20 + Express → Firebase Cloud Function "api"
│   ├── index.js                   # Exports `api` Cloud Function + local dev server (when run directly)
│   └── src/
│       ├── app.js                 # createApp(io) — configures middleware + routes
│       ├── config/
│       │   ├── db.js              # Mongoose → MongoDB Atlas
│       │   ├── firebase-admin.js  # Firebase Admin SDK (uses Application Default Credentials in prod)
│       │   └── constants.js       # ROLES, APPLICATION_STATUS, INCIDENT_SEVERITY, etc.
│       ├── middleware/
│       │   ├── auth.js            # JWT verification; attaches req.user
│       │   ├── rbac.js            # authorize(...roles); authorizeOwnerOrAdmin()
│       │   ├── rateLimiter.js     # 100 req/15 min global; 20 req/15 min on auth routes
│       │   ├── validateObjectId.js # Validates :id params are valid MongoDB ObjectIds
│       │   ├── errorHandler.js    # Central error + 404 handler
│       │   └── validator.js       # express-validator result checker
│       ├── models/                # Mongoose models (User, Application, Inspection, Incident, NOCCertificate, AuditLog)
│       ├── routes/                # Thin Express routers (validation + auth + controller)
│       ├── controllers/           # Business logic per resource
│       └── services/
│           ├── nocGenerator.js    # PDFKit PDF + Firebase Storage upload
│           ├── notificationService.js  # Nodemailer SMTP emails
│           ├── auditService.js    # Writes immutable AuditLog entries (never throws)
│           └── storageService.js  # Firebase Storage helper
│
├── .github/workflows/deploy.yml   # GitHub Actions: test → build → deploy
│                                  # ALL values come from GitHub Secrets — none hardcoded
├── firebase.json                  # Hosting rewrites (/api/** → function "api") + cache headers
├── .firebaserc                    # Maps "default" to your Firebase project ID
├── storage.rules                  # Storage security rules (NOC certs public-read; uploads auth-only)
├── firestore.rules                # Firestore security rules
└── SETUP.md                       # This file
```

---

## 4. Firebase Project Setup

### 4.1 Create a Firebase Project

1. Open https://console.firebase.google.com and sign in.
2. Click **"Add project"** → enter a name (e.g., `blaze-prod`).
3. Note the **Project ID** that appears beneath the name (e.g., `blaze-prod-abc12`). You will use it in several places.
4. Click **"Create project"**.

### 4.2 Register a Web App and Copy the Config

The Firebase JS SDK config values go into GitHub Secrets (not a `.env` file).

1. Firebase Console → ⚙️ **Project settings** → **"Your apps"** → click **`</>`** (Web).
2. Enter a nickname (`blaze-web`), tick **"Also set up Firebase Hosting"**, click **"Register app"**.
3. Firebase shows a config block:
   ```js
   const firebaseConfig = {
     apiKey: "AIzaSy...",
     authDomain: "blaze-prod-abc12.firebaseapp.com",
     projectId: "blaze-prod-abc12",
     storageBucket: "blaze-prod-abc12.appspot.com",
     messagingSenderId: "123456789012",
     appId: "1:123456789012:web:abcdef1234567890"
   };
   ```
4. **Do not put these in any file.** Go to GitHub Secrets (§7) and add each one there.

### 4.3 Enable Firebase Storage

1. Firebase Console → **Build** → **Storage** → **"Get started"**.
2. Choose **"Start in production mode"** (rules come from `storage.rules`).
3. Pick a region close to your users (e.g., `asia-south1` for India).

### 4.4 Get the VAPID Key (Push Notifications)

1. Firebase Console → ⚙️ **Project settings** → **"Cloud Messaging"** tab.
2. Scroll to **"Web configuration"** → **"Web Push certificates"**.
3. Click **"Generate key pair"** (do this once — never regenerate, or all push subscriptions break).
4. Copy the **Key pair** value → add to GitHub Secrets as `REACT_APP_FIREBASE_VAPID_KEY`.

### 4.5 Link the Firebase CLI to Your Project

```bash
firebase login                        # Opens browser OAuth
firebase use blaze-prod-abc12         # Replace with your Project ID
```

Update `.firebaserc` if it has a placeholder project ID:
```json
{ "projects": { "default": "blaze-prod-abc12" } }
```

### 4.6 Why No Service Account Key in Production

In production, the backend runs inside Firebase Cloud Functions. The Firebase Admin SDK automatically uses **Application Default Credentials** — it detects the built-in Cloud Functions service account and authenticates without needing a `serviceAccountKey.json` file. The file is only required for local development and is already git-ignored.

---

## 5. MongoDB Atlas Production Setup

### 5.1 Create an Atlas Account and Project

1. Go to https://cloud.mongodb.com and sign in (or register).
2. Create an **Organization** → inside it, create a **Project** named `blaze-prod`.

### 5.2 Create a Cluster

| Setting | Recommended Value |
|---------|------------------|
| Tier | **M10** dedicated (minimum production tier; ~$0.08/hr) |
| Cloud / Region | Match your Firebase Functions region (e.g., GCP `us-central1`) |
| Replication | 3-node replica set (default) |

> The free **M0** tier is not suitable for production (shared CPU, connection limits, no backups).

### 5.3 Create a Database User

1. Atlas → **Security** → **Database Access** → **"Add New Database User"**.
2. Authentication: **Password**.
3. Username: `blaze_api` | Password: **click "Autogenerate Secure Password"** → **copy it immediately**.
4. Role: **"Read and write to any database"** (`readWriteAnyDatabase`).
5. Click **"Add User"**.

This password is part of `MONGODB_URI`. Store it in Firebase Secret Manager (§8).

### 5.4 Configure Network Access

1. Atlas → **Security** → **Network Access** → **"Add IP Address"**.
2. **Production option A** — Restrict to Firebase Functions IPs:
   - Download current Google Cloud IP ranges from https://www.gstatic.com/ipranges/cloud.json
   - Add each range for your Functions region (e.g., `us-central1`)
3. **Production option B** — Allow all (`0.0.0.0/0`) combined with a strong password and TLS:
   - Click **"Allow Access from Anywhere"** → **"Confirm"**

### 5.5 Get the Connection String

1. Atlas → **Deployment** → **Database** → **"Connect"** on your cluster.
2. Choose **"Drivers"** → Driver: **Node.js** → Version: **5.5 or later**.
3. Copy the connection string. Modify it:
   ```
   mongodb+srv://blaze_api:YOUR_PASSWORD@cluster.abc12.mongodb.net/blaze?retryWrites=true&w=majority
   ```
   Replace `<password>` with the database user password and append `/blaze` as the database name.
4. Store this complete string in Firebase Secret Manager as `MONGODB_URI` (§8).

---

## 6. Gmail SMTP App Password

BLAZE uses Nodemailer to send emails (status updates, inspection notifications). It authenticates to Gmail using an **App Password** — a 16-character token that works without your real Gmail password.

### 6.1 Enable 2-Step Verification

1. Go to https://myaccount.google.com/security.
2. Under **"How you sign in to Google"** → click **"2-Step Verification"** → enable it.

### 6.2 Generate an App Password

1. Go to https://myaccount.google.com/apppasswords (only visible after 2-Step is enabled).
2. In **"App name"** enter `BLAZE Production` → click **"Create"**.
3. Google shows a 16-character password. **Copy it immediately** — it is shown only once.
4. Remove spaces (e.g., `abcd efgh ijkl mnop` → `abcdefghijklmnop`).

Store it as `EMAIL_PASS` in Firebase Secret Manager (§8). Your Gmail address is `EMAIL_USER`.

---

## 7. GitHub Secrets — Complete List

**Location:** GitHub repo → **Settings** → **Secrets and variables** → **Actions** → **"New repository secret"**

These secrets are used by the GitHub Actions workflow at CI/CD time. They are injected as environment variables during `npm run build` (frontend) and during tests.

### 7.1 CI / Test Secrets

| Secret Name | Value | Where to Get It |
|-------------|-------|-----------------|
| `JWT_SECRET` | A random 96-char hex string | `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"` |
| `MONGODB_URI_TEST` | A test/dev Atlas connection string | MongoDB Atlas — create a separate `blaze_test` database; use the same format as §5.5 |

> `MONGODB_URI_TEST` is used only during CI tests — use a separate dev-tier Atlas cluster (free M0 is fine for tests).

### 7.2 Frontend Build Secrets (baked into the React bundle at build time)

| Secret Name | Value | Where to Get It |
|-------------|-------|-----------------|
| `REACT_APP_SOCKET_URL` | `https://us-central1-YOUR_PROJECT.cloudfunctions.net` | Firebase Console → **Functions** → **Dashboard** → URL of the `api` function |
| `REACT_APP_FIREBASE_API_KEY` | `AIzaSy...` | Firebase Console → Project settings → Your apps → Web app → `apiKey` |
| `REACT_APP_FIREBASE_AUTH_DOMAIN` | `blaze-prod-abc12.firebaseapp.com` | Firebase Console → Project settings → Your apps → `authDomain` |
| `REACT_APP_FIREBASE_PROJECT_ID` | `blaze-prod-abc12` | Firebase Console → Project settings → **General** → **Project ID** |
| `REACT_APP_FIREBASE_STORAGE_BUCKET` | `blaze-prod-abc12.appspot.com` | Firebase Console → Project settings → Your apps → `storageBucket` |
| `REACT_APP_FIREBASE_MESSAGING_SENDER_ID` | `123456789012` | Firebase Console → Project settings → Your apps → `messagingSenderId` |
| `REACT_APP_FIREBASE_APP_ID` | `1:...:web:...` | Firebase Console → Project settings → Your apps → `appId` |
| `REACT_APP_FIREBASE_VAPID_KEY` | `BExample...` | Firebase Console → Project settings → **Cloud Messaging** → Web Push certificates → **Key pair** |

### 7.3 Deployment Secret

| Secret Name | Value | How to Generate |
|-------------|-------|-----------------|
| `FIREBASE_TOKEN` | Long CI token starting with `1//` | Run `firebase login:ci` in a terminal; copy the printed token |

### 7.4 How to Add a GitHub Secret

1. Open your GitHub repository.
2. Click **Settings** tab (top of the repo page).
3. In the left sidebar → **"Secrets and variables"** → **"Actions"**.
4. Click **"New repository secret"**.
5. Enter the **Name** exactly as shown in the table above.
6. Paste the **Secret** value.
7. Click **"Add secret"**.

Repeat for every secret in the tables above.

---

## 8. Firebase Secret Manager — Complete List

These secrets are the **backend runtime secrets** stored in Google Cloud Secret Manager and injected into the Firebase Cloud Function at request time. The function uses `runWith({ secrets: [...] })` which makes each secret available as `process.env.NAME`.

**Command to add a secret:**
```bash
firebase functions:secrets:set SECRET_NAME
# Firebase will prompt you to type the value (hidden input — not echoed to terminal)
```

### 8.1 Required Secrets

| Secret Name | Value | Where to Get It |
|-------------|-------|-----------------|
| `MONGODB_URI` | Full Atlas connection string including `/blaze` database | §5.5 |
| `JWT_SECRET` | **Same value** as the `JWT_SECRET` GitHub Secret | Generate with `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"` — use the same value in both places |
| `JWT_EXPIRES_IN` | `7d` | Token lifetime — `7d` means users stay logged in 7 days |
| `FIREBASE_PROJECT_ID` | `blaze-prod-abc12` | Firebase Console → Project settings → General → **Project ID** |
| `FIREBASE_STORAGE_BUCKET` | `blaze-prod-abc12.appspot.com` | Firebase Console → Project settings → General → **Default GCS bucket** |
| `EMAIL_HOST` | `smtp.gmail.com` | Fixed value |
| `EMAIL_PORT` | `587` | Fixed value (TLS STARTTLS port) |
| `EMAIL_USER` | `blaze.notifications@gmail.com` | Your Gmail address used in §6 |
| `EMAIL_PASS` | 16-character App Password | §6.2 |
| `FRONTEND_URL` | `https://blaze-prod-be77b.web.app` | Firebase Hosting URL shown after first deploy; use comma-separated for multiple domains |
| `INSPECTOR_INVITE_CODE` | e.g. `DEPT-2025-BLAZE` | Authorization code required for inspector self-registration; inspectors must enter this during sign-up |

### 8.2 Add All Secrets in One Session

Run these commands one after another. Firebase prompts for each value securely:

```bash
firebase functions:secrets:set MONGODB_URI
firebase functions:secrets:set JWT_SECRET
firebase functions:secrets:set JWT_EXPIRES_IN
firebase functions:secrets:set FIREBASE_PROJECT_ID
firebase functions:secrets:set FIREBASE_STORAGE_BUCKET
firebase functions:secrets:set EMAIL_HOST
firebase functions:secrets:set EMAIL_PORT
firebase functions:secrets:set EMAIL_USER
firebase functions:secrets:set EMAIL_PASS
firebase functions:secrets:set FRONTEND_URL
firebase functions:secrets:set INSPECTOR_INVITE_CODE
```

### 8.3 Verify Secrets Are Stored

```bash
firebase functions:secrets:access MONGODB_URI   # Prints the value (use only to verify)
firebase functions:secrets:list                  # Lists all stored secret names
```

### 8.4 Update a Secret

```bash
firebase functions:secrets:set MONGODB_URI      # Prompts for new value; creates a new version
# Re-deploy the function to pick up the new version:
firebase deploy --only functions
```

---

## 9. Production Build & Deploy

All steps below are normally run automatically by GitHub Actions when you push to `main`. These manual steps are for your first deployment or for emergency manual deploys.

### 9.1 Install Dependencies

```bash
# Backend
cd functions && npm ci

# Frontend
cd ../client && npm ci
```

### 9.2 Build the React Frontend

The build must receive all `REACT_APP_*` values as environment variables. In GitHub Actions these come from GitHub Secrets. For a manual build, export them first:

```bash
export REACT_APP_API_URL=/api
export REACT_APP_SOCKET_URL=https://us-central1-blaze-prod-abc12.cloudfunctions.net
export REACT_APP_FIREBASE_API_KEY=AIzaSy...
export REACT_APP_FIREBASE_AUTH_DOMAIN=blaze-prod-abc12.firebaseapp.com
export REACT_APP_FIREBASE_PROJECT_ID=blaze-prod-abc12
export REACT_APP_FIREBASE_STORAGE_BUCKET=blaze-prod-abc12.appspot.com
export REACT_APP_FIREBASE_MESSAGING_SENDER_ID=123456789012
export REACT_APP_FIREBASE_APP_ID=1:123456789012:web:abcdef1234567890
export REACT_APP_FIREBASE_VAPID_KEY=BExample...

cd client && npm run build
```

> The values above are from your GitHub Secrets. You can find them in GitHub → Settings → Secrets → Actions.

### 9.3 Deploy Everything

```bash
# From the repository root
firebase deploy
# Deploys: Hosting (frontend) + Cloud Functions (backend) + Storage rules
```

Targeted deployments:

```bash
firebase deploy --only hosting         # Frontend only
firebase deploy --only functions       # Backend only
firebase deploy --only storage         # Storage rules only
firebase deploy --only hosting,functions  # Frontend + backend
```

### 9.4 CI/CD Automatic Deploy

Push any commit to the `main` branch:

```bash
git push origin main
```

GitHub Actions will:
1. Run backend tests (uses `JWT_SECRET` + `MONGODB_URI_TEST` from GitHub Secrets)
2. Run frontend tests + build (uses all `REACT_APP_*` from GitHub Secrets)
3. Deploy to Firebase (uses `FIREBASE_TOKEN` from GitHub Secrets)

No `.env` file is ever created or read during CI/CD.

### 9.5 Verify Deployment URLs

Firebase prints the live URL after deploy:
```
✔  Deploy complete!
Hosting URL: https://blaze-prod-abc12.web.app
```

Check the Cloud Function URL:
```
Firebase Console → Functions → Dashboard → api function → URL column
```

---

## 10. Create the First Admin Account

> **Security policy:** The `/api/auth/register` endpoint only allows `applicant` and `inspector` roles to self-register. Attempting to register with `role: "admin"` silently falls back to `applicant`. The first admin must be created using the seed script or manually in the database.

### 10.1 Quick Method — Seed Script (Recommended)

A simple interactive script is included at `functions/seedAdmin.js`. It connects to your MongoDB, asks for a name/email/password, and creates the admin account automatically.

```bash
cd functions
npm install          # if not already done
cp .env.example .env # if you don't have a .env yet
# Edit .env — set MONGODB_URI to your Atlas connection string

node seedAdmin.js
```

The script will prompt:

```
🔥  BLAZE — Create Admin Account

Admin name  (default: System Administrator):
Admin email (default: admin@blaze.gov):
Admin password (min 8 chars):

Connecting to MongoDB...
✅  Connected
✅  Admin account created!

   Email:    admin@blaze.gov
   Password: (the one you just entered)

   You can now log in at your BLAZE website → Admin Portal.
```

- Safe to run multiple times — if the email already exists it skips (or upgrades the role to admin).
- The password is hashed automatically by the User model.
- For **production**, point `MONGODB_URI` in `functions/.env` to your production Atlas cluster, run the script, then delete or revert the `.env` file.

### 10.2 Manual Method — MongoDB Atlas Console

If you prefer, you can insert the admin document directly:

1. Generate a bcrypt hash:
   ```bash
   cd functions
   node -e "require('bcryptjs').hash('YourAdminPassword@123',12).then(h=>console.log(h))"
   ```
2. Atlas Console → **Database** → **Browse Collections** → `blaze` → `users` → **INSERT DOCUMENT**:
   ```json
   {
     "name": "System Administrator",
     "email": "admin@blaze.gov",
     "password": "$2a$12$PASTE_BCRYPT_HASH_HERE",
     "role": "admin",
     "isActive": true,
     "emailVerified": true,
     "createdAt": { "$date": "2025-01-01T00:00:00.000Z" },
     "updatedAt": { "$date": "2025-01-01T00:00:00.000Z" }
   }
   ```

### 10.3 Verify Admin Login

```bash
curl -X POST https://blaze-prod-abc12.web.app/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@blaze.gov","password":"YourAdminPassword@123"}'
# Expected: {"success":true,"token":"eyJhb...","user":{"role":"admin",...}}
```

---

## 11. Post-Deployment Verification

```bash
BASE=https://blaze-prod-abc12.web.app

# 1. Health endpoint
curl $BASE/api/health
# Expected: {"success":true,"message":"BLAZE API is running","version":"1.0.0"}

# 2. Login
TOKEN=$(curl -s -X POST $BASE/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@blaze.gov","password":"YourAdminPassword@123"}' \
  | node -e "process.stdin||(process.stdin=require('fs').createReadStream('/dev/stdin'));let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.parse(d).token))")

# 3. Verify token
curl -H "Authorization: Bearer $TOKEN" $BASE/api/auth/me
# Expected: {"success":true,"user":{"role":"admin",...}}

# 4. NOC verify endpoint (public, no auth)
curl $BASE/api/noc/verify/nonexistent
# Expected: {"success":false,"message":"Certificate not found or invalid"}
```

Frontend route checks (open in browser):

| URL | Expected |
|-----|---------|
| `https://blaze-prod-abc12.web.app/` | Public landing page with hero, features, and CTA |
| `/login` | Login form |
| `/register` | Registration form |
| `/dashboard` | Redirects → `/login` if not authenticated; stat cards + map if logged in |
| `/applications` | Application list (scoped by role) |
| `/applications/new` | New NOC application form |
| `/applications/:id` | Application detail view |
| `/inspections` | Inspection list (inspector sees assigned only) |
| `/inspections/:id` | Inspection detail with checklist and photos |
| `/incidents` | Incident table with inline reporting |
| `/incidents/:id` | Incident detail with update timeline |
| `/noc` | NOC certificate grid |
| `/noc/:id` | Certificate detail with validity, QR code, PDF download |
| `/analytics` | Admin analytics dashboard with charts |
| `/heatmap` | Leaflet heatmap of incident locations |
| `/verify-noc/:token` | Public certificate verification (no auth required) |

---

## 12. API Reference

Base URL in production: `https://blaze-prod-abc12.web.app/api`

### Authentication

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/auth/register` | None | Register as `applicant` or `inspector` only |
| POST | `/auth/login` | None | Returns JWT token |
| GET | `/auth/me` | JWT | Current user profile |
| PUT | `/auth/profile` | JWT | Update name, phone, address, organization |
| PUT | `/auth/change-password` | JWT | `currentPassword` + `newPassword` required |
| GET | `/auth/users` | Admin JWT | List all users (`?role=inspector&page=1`) |

### Applications

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/applications` | JWT | List (applicants see own; admins see all) |
| POST | `/applications` | JWT | Create (status: `draft`) |
| GET | `/applications/:id` | JWT | Full details |
| PUT | `/applications/:id` | JWT | Update (owner or admin) |
| POST | `/applications/:id/submit` | JWT (owner) | `draft` → `submitted`; sends email |
| PUT | `/applications/:id/review` | Admin JWT | Set status + assign inspector |
| GET | `/applications/stats` | Admin JWT | Count by status |

**Application status lifecycle:**
```
draft → submitted → under_review → inspection_scheduled → inspection_in_progress → approved → certificate_issued
                                                                                  ↘ rejected
```

### Inspections

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/inspections` | JWT | List (inspectors see assigned) |
| POST | `/inspections` | Admin JWT | Schedule new inspection |
| GET | `/inspections/:id` | JWT | Details including checklist + photos |
| PUT | `/inspections/:id` | Admin/Inspector JWT | Update |
| POST | `/inspections/:id/checkin` | Inspector JWT | GPS check-in `{lat, lng}` |
| POST | `/inspections/:id/checklist` | Inspector JWT | Submit result + checklist items + score |

### Incidents

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/incidents` | JWT | List (geo filter: `?lat=&lng=&radius=` in km) |
| POST | `/incidents` | JWT | Report; emits `incident:new` Socket.IO event |
| GET | `/incidents/:id` | JWT | Full incident with updates |
| PUT | `/incidents/:id` | Admin JWT | Update; emits `incident:updated` |
| POST | `/incidents/:id/updates` | JWT | Add text update; emits `incident:update` |
| GET | `/incidents/stats` | JWT | Counts by severity, status, type |

### NOC Certificates

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/noc/verify/:token` | **None** | Public QR verification |
| GET | `/noc` | JWT | List certificates |
| POST | `/noc/issue/:applicationId` | Admin JWT | Issue cert; generates PDF + QR code |
| GET | `/noc/:id` | JWT | Certificate + PDF URL |
| PUT | `/noc/:id/revoke` | Admin JWT | Revoke with reason |

### Analytics (Admin Only)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/analytics/dashboard` | KPI counts |
| GET | `/analytics/trends/applications` | Monthly trends (`?months=6`) |
| GET | `/analytics/heatmap/incidents` | Leaflet heatmap data points |
| GET | `/analytics/metrics/inspections` | Pass rate, avg score, breakdown |
| GET | `/analytics/risk-score` | 0–100 risk score (`?city=Bangalore`) |

---

## 13. Production Security Checklist

### GitHub Secrets
- [ ] All secrets listed in §7 are added to GitHub (no placeholder values)
- [ ] `FIREBASE_TOKEN` is a CI-only token generated with `firebase login:ci`, not your personal login token
- [ ] `JWT_SECRET` in GitHub matches `JWT_SECRET` in Firebase Secret Manager (they must be identical)

### Firebase Secret Manager
- [ ] All secrets listed in §8 are set with `firebase functions:secrets:set`
- [ ] `MONGODB_URI` includes the database name (`/blaze`) and `retryWrites=true&w=majority`
- [ ] `FRONTEND_URL` is the exact production domain(s) — no trailing slashes, correct scheme (`https://`)

### Code & Repository
- [ ] No `.env` file exists at `functions/.env` in the deployed code
- [ ] No `.env` file exists at `client/.env.production` in the deployed code
- [ ] `serviceAccountKey.json` is listed in `.gitignore` and has never been committed
- [ ] `NODE_ENV=production` is set (Cloud Functions sets this automatically)
- [ ] The workflow YAML (`deploy.yml`) contains no hardcoded secret values — only `${{ secrets.NAME }}` references

### MongoDB Atlas
- [ ] Using M10+ dedicated cluster (not free M0)
- [ ] TLS enforced (Atlas default — do not disable)
- [ ] Database user has `readWriteAnyDatabase` only (not `atlasAdmin`)
- [ ] Network access restricted to Firebase Functions IPs or `0.0.0.0/0` with strong password

### Firebase
- [ ] Storage rules deployed (`firebase deploy --only storage`)
- [ ] No anonymous access to the Firebase project (Firebase Console → Authentication → Sign-in providers)
- [ ] Firebase billing alerts configured

---

## 14. Monitoring & Observability

### Firebase Function Logs

```bash
firebase functions:log           # Last 20 log entries
firebase functions:log --follow  # Stream live
```

Or: Firebase Console → **Functions** → **Logs** tab.

### MongoDB Atlas Monitoring

Atlas Console → **Deployment** → your cluster → **"Metrics"** tab:

| Metric | Suggested Alert |
|--------|----------------|
| Connections | > 80% of max (M10 = 1,500) |
| Query latency | > 100 ms avg |
| Disk IOPS | > 80% provisioned |

Set alerts: Atlas → **"Alerts"** → **"Add Alert"**.

### Uptime Monitoring

Use a free external monitor so you get alerted if the API goes down:

1. Register at https://uptimerobot.com (free tier: 50 monitors, 5-min checks).
2. Add an **HTTP(s)** monitor pointing to: `https://blaze-prod-abc12.web.app/api/health`
3. Set email/SMS notifications.

---

## 15. Troubleshooting

### Secret not available in Cloud Function

**Symptom:** `Cannot read properties of undefined` or `process.env.MONGODB_URI is undefined` in function logs.

**Fix:**
```bash
# Verify the secret exists
firebase functions:secrets:list

# If missing, add it
firebase functions:secrets:set MONGODB_URI

# Re-deploy the function
firebase deploy --only functions
```

---

### MongoDB connection timeout

**Symptom:** `MongooseServerSelectionError: connection timed out`

**Causes:**
1. IP not in Atlas allowlist → Atlas → Security → Network Access → add your range or `0.0.0.0/0`
2. Wrong password → special characters in the password must be URL-encoded (e.g., `@` → `%40`)
3. Missing database name in URI → ensure `/blaze` appears before `?`
4. Free M0 cluster paused (idle > 60 days) → Atlas → your cluster → **"Resume"**

---

### Firebase Functions deployment fails

**Symptom:** `Error: HTTP Error: 400` or `The request has errors`

**Fixes:**
1. Ensure `functions/package.json` has `"engines": { "node": "20" }`
2. Run `npm ci` in `functions/` to sync the lockfile
3. Check that `serviceAccountKey.json` is not being deployed (it must be in `.gitignore`)
4. Check logs: `firebase functions:log`

---

### CORS error in browser

**Symptom:** `Access to XMLHttpRequest blocked by CORS policy`

**Fix:**
1. Verify `FRONTEND_URL` in Firebase Secret Manager exactly matches the `Origin` header (e.g., `https://blaze-prod-abc12.web.app` — no trailing slash, correct scheme)
2. Update and re-deploy: `firebase functions:secrets:set FRONTEND_URL` → `firebase deploy --only functions`

---

### Frontend shows blank page after deploy

**Symptom:** White screen; browser console shows `Uncaught SyntaxError` or missing env var

**Fix:**
1. Verify all `REACT_APP_*` GitHub Secrets are set (§7.2)
2. Trigger a fresh deploy: `git push origin main` (GitHub Actions will rebuild with the secrets)
3. Ensure 404 rewrite is in `firebase.json`: `{ "source": "**", "destination": "/index.html" }`

---

### Email not sending

**Symptom:** `Error: Invalid login: 534-5.7.9 Application-specific password required`

**Fix:**
1. 2-Step Verification must be enabled on the Gmail account before App Passwords work
2. `EMAIL_PASS` must be the 16-char App Password with no spaces
3. Update: `firebase functions:secrets:set EMAIL_PASS` → `firebase deploy --only functions`

---

### Push Notifications not arriving

**Fix:**
1. Push notifications require HTTPS — they never work on `http://`
2. Verify `REACT_APP_FIREBASE_VAPID_KEY` in GitHub Secrets matches the key in Firebase Console → Cloud Messaging → Web Push certificates exactly
3. Trigger a new deploy so the React bundle is rebuilt with the correct VAPID key

---

## 16. Local Development

Local development uses `.env` files, which are **never deployed** and are git-ignored.

```bash
# 1. Clone the repository
git clone https://github.com/bnaveen07/firms.git
cd firms

# 2. Backend
cd functions
cp .env.example .env          # Copy the template
# Edit .env — fill in your DEV-tier MongoDB, Firebase project, Gmail App Password
npm install
npm run dev                   # Starts Express + Socket.IO on http://localhost:5000

# 3. Frontend (new terminal)
cd client
cp .env.local.example .env.local   # Copy the template
# Edit .env.local — fill in your dev Firebase config
npm install
npm start                     # React dev server on http://localhost:3000
```

The local dev server (`npm run dev` / `node index.js`) loads `functions/.env` using `dotenv`. This path is the **only** place in the entire codebase where `dotenv.config()` is called.

In Firebase Cloud Functions (production), `dotenv` is never called — secrets are injected by `runWith({ secrets: [...] })` directly into `process.env`.
