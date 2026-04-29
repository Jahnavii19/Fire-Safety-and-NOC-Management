# 🔥 Fire Safety and NOC Management

> **Fire Safety and NOC Management** is a production-ready full-stack web platform for fire departments to manage NOC applications, track incidents in real-time, and issue QR-verified safety certificates.

🌐 **Live Demo**: [https://jahnavii19.github.io/blaze](https://jahnavii19.github.io/blaze)

## Key Features

- **Real-Time Incident Map** — Live fire incident tracking with severity levels on an interactive Leaflet map
- **Digital NOC Pipeline** — Application → Review → Inspection → Approval → PDF Certificate with QR verification
- **Inspector Mobile Module** — PWA-ready with GPS check-in, photo upload, and offline support
- **Admin Operations Center** — Unified dashboard with analytics, heatmaps, and team management
- **Analytics Engine** — Throughput metrics, inspection pass rates, risk scoring
- **QR-Verified Certificates** — Tamper-evident PDFs with public `/verify-noc/:token` endpoint

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | React 18 + Redux Toolkit + RTK Query + Leaflet.js |
| Backend | Node.js 20 + Express.js 4 + Socket.IO 4 |
| Database | Cloud Firestore (Firebase) |
| Auth | JWT + RBAC (admin / applicant / inspector) |
| Storage | Firebase Storage (photos, PDFs) |
| Hosting | Firebase Hosting (CDN) + GitHub Pages (frontend preview) |
| Functions | Firebase Cloud Functions |
| Notifications | Firebase FCM + Nodemailer |
| CI/CD | GitHub Actions |

## GitHub Pages Deployment

The frontend is automatically deployed to GitHub Pages on every push to `main`.

**Live URL**: `https://jahnavii19.github.io/firms`

To deploy manually:
```bash
cd client
npm run deploy   # runs predeploy (build) then gh-pages -d build
```

> **Note**: GitHub Pages hosts the static frontend only. The production backend and database run on Firebase (Cloud Functions + Firestore).

## Firebase Full Deploy (Frontend + Backend + Rules)

From the repository root on Windows PowerShell:

```powershell
./deploy.firebase.ps1 -Project default
```

This builds the React app and deploys:
- Firebase Hosting (frontend)
- Cloud Functions (backend API)
- Firestore rules
- Storage rules

## One-time Data Migration (MongoDB → Firestore)

If you already have MongoDB data and want to migrate it:

```bash
cd functions
npm install
npm run migrate:mongo:firestore
```

Requirements:
- `functions/.env` must include `MONGODB_URI`
- Optional: set `MONGODB_DB_NAME` (default: `blaze`)

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/jahnavii19/firms.git
cd firms

# 2. Setup backend
cd functions
cp .env.example .env    # Edit with your values
npm install
npm run dev

# 3. Setup frontend (new terminal)
cd client
cp .env.local.example .env.local    # Edit with your Firebase config
npm install
npm start
```

See **[SETUP.md](./SETUP.md)** for the complete setup guide.

## User Roles

| Role | Capabilities |
|------|-------------|
| **Admin** | Full access: review applications, assign inspectors, issue NOC, view analytics |
| **Applicant** | Submit & track their own applications, download certificates |
| **Inspector** | View assigned inspections, GPS check-in, submit checklists & photos |

## Documentation

See **[CODE_EXPLANATION.md](./CODE_EXPLANATION.md)** for a detailed walkthrough of every file and component in the codebase.

## License

MIT
