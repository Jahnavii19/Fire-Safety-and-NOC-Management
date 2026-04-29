param(
  [string]$Project = "default"
)

$ErrorActionPreference = "Stop"

Write-Host "Installing client dependencies and building frontend..."
npm --prefix client install
npm --prefix client run build

Write-Host "Installing function dependencies..."
npm --prefix functions install

Write-Host "Deploying Hosting + Functions + Firestore/Storage rules to Firebase project '$Project'..."
firebase deploy --project $Project --only functions,hosting,firestore:rules,storage

Write-Host "Deployment completed." 
