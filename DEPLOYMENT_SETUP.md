# 🚀 BLAZE Firebase Deployment Setup - Complete

## ✅ Completed Configuration

### 1. Firebase Project
- **Project ID**: `blaze-prod-be77b`
- **Hosting URL**: `https://blaze-prod-be77b.web.app`
- **Service Account Key**: Copied to `functions/blaze-prod-be77b-firebase-adminsdk-fbsvc-2dcd333b58.json`
- **Firebase CLI Status**: Logged out (ready for your account)

### 2. Client Configuration (React) - `client/.env.local`
```
✅ REACT_APP_FIREBASE_API_KEY = AIzaSyA7H7WlS6wUtQfrEKX8HG-MqM69Ql8k46U
✅ REACT_APP_FIREBASE_PROJECT_ID = blaze-prod-be77b
✅ REACT_APP_FIREBASE_STORAGE_BUCKET = blaze-prod-be77b.firebasestorage.app
✅ REACT_APP_FIREBASE_MESSAGING_SENDER_ID = 987428407455
✅ REACT_APP_FIREBASE_APP_ID = 1:987428407455:web:d6acec4c9bcbe0eb473aaa
✅ REACT_APP_FIREBASE_MEASUREMENT_ID = G-QTVKY27RK1
✅ REACT_APP_API_URL = https://blaze-prod-be77b.web.app/api
✅ REACT_APP_SOCKET_URL = https://blaze-prod-be77b.web.app
```

### 3. Cloud Functions Configuration - `functions/.env`
```
✅ NODE_ENV = production
✅ FIREBASE_PROJECT_ID = blaze-prod-be77b
✅ FIREBASE_STORAGE_BUCKET = blaze-prod-be77b.firebasestorage.app
✅ JWT_SECRET = (generated: 96-char secure random)
✅ JWT_EXPIRES_IN = 7d
✅ FRONTEND_URL = https://blaze-prod-be77b.web.app
✅ INSPECTOR_INVITE_CODE = BLAZE2026FIRE
✅ EMAIL_HOST = smtp.gmail.com
✅ EMAIL_PORT = 587
✅ EMAIL_USER = team@vaya.social
⚠️  EMAIL_PASS = (NEEDS YOUR GMAIL APP PASSWORD - see below)
```

### 4. Firebase Configuration
- **✅ .firebaserc**: Set to project `blaze-prod-be77b`
- **✅ firebase.json**: Configured for hosting + functions deployment
- **✅ Client built**: Production bundle ready at `client/build/`

---

## 🔐 IMPORTANT: Next Steps

### Step 1️⃣ Generate Gmail App Password
Since you're using `team@vaya.social`, you need an App Password for SMTP:

1. Go to: https://myaccount.google.com/apppasswords
2. Select **App**: Mail
3. Select **Device**: Windows Computer
4. Google will generate a 16-character App Password
5. Copy it

### Step 2️⃣ Update EMAIL_PASS in `functions/.env`
```bash
# Replace this line in functions/.env:
EMAIL_PASS=YOUR_GMAIL_APP_PASSWORD_HERE

# With your actual Gmail App Password (16 chars, no spaces)
EMAIL_PASS=abcdefghijklmnop
```

### Step 3️⃣ Login to Firebase
```bash
firebase login
```
- This will open your browser
- **Sign in with**: team@vaya.social (or the account that owns blaze-prod-be77b)
- Approve the Firebase CLI access

### Step 4️⃣ Deploy to Firebase
```bash
# From the project root directory:
firebase deploy --project default

# OR use the PowerShell script:
./deploy.firebase.ps1 -Project default
```

The deployment will:
- ✅ Build the React frontend
- ✅ Install backend dependencies
- ✅ Deploy functions to Firebase Cloud Functions
- ✅ Deploy hosting to Firebase Hosting
- ✅ Deploy Firestore security rules
- ✅ Deploy Cloud Storage rules

---

## 📋 What Gets Deployed

| Component | Destination | Details |
|-----------|------------|---------|
| **Frontend** | Firebase Hosting | React SPA at `https://blaze-prod-be77b.web.app` |
| **Backend API** | Cloud Functions | Express app at `/api/**` |
| **Database** | Cloud Firestore | Collections: users, applications, inspections, incidents, noccertificates, auditLogs |
| **File Storage** | Cloud Storage | Photos, PDFs, profile images |
| **Auth** | Custom JWT + Firestore | No Firebase Auth - stateless tokens |

---

## ✨ After Deployment

1. **Access your app:**
   - Open: https://blaze-prod-be77b.web.app
   - Login with the admin credentials you created
   - Start onboarding users

---

## 🆘 Troubleshooting

| Issue | Solution |
|-------|----------|
| "Authentication Error" | Run `firebase login` with correct account |
| Build fails | Run `npm --prefix client install --legacy-peer-deps` |
| Functions won't start | Verify all `.env` variables are set |
| Email not sending | Check Gmail App Password is correct (16 chars, no spaces) |
| Firestore errors | Ensure `GOOGLE_APPLICATION_CREDENTIALS` env var points to service account JSON |

---

## 📞 Support

- **Firebase Console**: https://console.firebase.google.com/project/blaze-prod-be77b
- **Function Logs**: Firebase Console → Functions → logs
- **Hosting Logs**: Firebase Console → Hosting → logs

---

**Ready to deploy? Execute: `firebase login` then `firebase deploy --project default`**
