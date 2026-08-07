#!/usr/bin/env bash

# --- Color definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Error Handling ---
set -e
trap 'echo -e "${RED}❌ Error occurred at line $LINENO. Exiting.${NC}" >&2; exit 1' ERR

# --- Helper Functions ---
section() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

prompt_continue() {
    echo -e "${YELLOW}Press [Enter] to continue or [Ctrl+C] to abort...${NC}"
    read -r
}

# --- Configuration ---
PROJECT_NAME="secure-eks-platform"
AWS_REGION="ap-south-1"
ECR_URI="310454703862.dkr.ecr.ap-south-1.amazonaws.com"
ECR_REPO="${ECR_URI}/${PROJECT_NAME}"
APP_NAMESPACE="flask"
APP_DIR="app" # Define app directory relative to script root

# --- Start ---
echo -e "${BOLD}${GREEN}🚀 Starting automated deployment for ${PROJECT_NAME}${NC}"
date

# -------------------------------------------------------------------------
# PHASE 2 — Build Docker image
# -------------------------------------------------------------------------
section "PHASE 2: Building Docker Image"

# Check if we are in the app/ directory or the project root
if [[ "$(basename "$PWD")" == "app" ]]; then
    # If we are inside app/, run build directly
    echo -e "${CYAN}▶ Building image from within 'app/' directory: ${PROJECT_NAME}:latest${NC}"
    docker build -t "${PROJECT_NAME}:latest" .
else
    # If we are in root, use -f to point to the Dockerfile in app/
    echo -e "${CYAN}▶ Building image from project root: ${PROJECT_NAME}:latest${NC}"
    docker build -t "${PROJECT_NAME}:latest" -f "${APP_DIR}/Dockerfile" "${APP_DIR}"
fi

echo -e "${GREEN}✅ Build successful.${NC}"

echo -e "\n${CYAN}▶ Verifying image:${NC}"
docker images --filter "reference=${PROJECT_NAME}:latest"

prompt_continue

# -------------------------------------------------------------------------
# PHASE 3 — Run container locally (Smoke Test)
# -------------------------------------------------------------------------
section "PHASE 3: Running Container Locally"
echo -e "${YELLOW}⚠️  Container will start in the background on port 5000.${NC}"
echo -e "${YELLOW}   Press [Enter] to test, and [Ctrl+C] to stop it after verification.${NC}"
prompt_continue

# Use explicit path to .env file relative to root, regardless of where script is run
ENV_FILE_PATH="${APP_DIR}/.env"

docker run -d --rm \
    --name "${PROJECT_NAME}-test" \
    -p 5000:5000 \
    --env-file "${ENV_FILE_PATH}" \
    "${PROJECT_NAME}:latest"

echo -e "${CYAN}▶ Waiting 5 seconds for app to initialize...${NC}"
sleep 5

echo -e "\n${CYAN}▶ Checking endpoints:${NC}"
curl -s http://localhost:5000/ | grep -o "<title>.*</title>" || echo "No title found"
curl -s http://localhost:5000/health
curl -s http://localhost:5000/ready
curl -s http://localhost:5000/metrics

echo -e "\n${YELLOW}Note: /ready may return 503 if DB is not running locally. This is expected.${NC}"
echo -e "\n${GREEN}✅ Local container test completed.${NC}"

echo -e "${CYAN}▶ Stopping local container...${NC}"
docker stop "${PROJECT_NAME}-test" > /dev/null 2>&1 || true

prompt_continue

# -------------------------------------------------------------------------
# PHASE 4 — Push to ECR
# -------------------------------------------------------------------------
section "PHASE 4: Pushing Image to ECR"

# Check if .env has AWS profile, fallback to default
AWS_PROFILE_FLAG=""
if grep -q "AWS_PROFILE" "${ENV_FILE_PATH}" 2>/dev/null; then
    source "${ENV_FILE_PATH}"
    AWS_PROFILE_FLAG="--profile $AWS_PROFILE"
fi

echo -e "${CYAN}▶ Logging into ECR...${NC}"
aws ecr get-login-password $AWS_PROFILE_FLAG --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${ECR_URI}"

echo -e "${CYAN}▶ Tagging image...${NC}"
docker tag "${PROJECT_NAME}:latest" "${ECR_REPO}:latest"

echo -e "${CYAN}▶ Pushing image to ECR...${NC}"
docker push "${ECR_REPO}:latest"

echo -e "${CYAN}▶ Verifying ECR image list...${NC}"
aws ecr list-images $AWS_PROFILE_FLAG --repository-name "${PROJECT_NAME}"

echo -e "${GREEN}✅ Image successfully pushed to ECR.${NC}"

prompt_continue

# -------------------------------------------------------------------------
# PHASE 5 — Verify Kubernetes Deployment
# -------------------------------------------------------------------------
section "PHASE 5: Rolling out Deployment to EKS"

if ! kubectl get namespace "${APP_NAMESPACE}" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Namespace '${APP_NAMESPACE}' not found. Creating it...${NC}"
    kubectl create namespace "${APP_NAMESPACE}"
fi

# Assuming your deployment YAMLs exist in ./kubernetes/ relative to root
K8S_DIR="kubernetes"

# Check if kubernetes directory exists before trying to cd into it
if [ -d "$K8S_DIR" ]; then
    cd "$K8S_DIR"
    
    echo -e "${CYAN}▶ Applying Kubernetes manifests...${NC}"
    # Apply SecretStore first so ExternalSecrets can work
    kubectl apply -f 01_secretstore.yaml > /dev/null 2>&1 || echo -e "${YELLOW}ℹ️ SecretStore already exists or skipped.${NC}"
    kubectl apply -f 02_externalsecret.yaml > /dev/null 2>&1 || echo -e "${YELLOW}ℹ️ ExternalSecret already exists or skipped.${NC}"
    kubectl apply -f 03_deployment.yaml > /dev/null 2>&1 || echo -e "${YELLOW}ℹ️ Deployment already exists or skipped.${NC}"
    kubectl apply -f 04_service.yaml > /dev/null 2>&1 || echo -e "${YELLOW}ℹ️ Service already exists or skipped.${NC}"
    kubectl apply -f 05_ingress.yaml > /dev/null 2>&1 || echo -e "${YELLOW}ℹ️ Ingress already exists or skipped.${NC}"
    
    echo -e "${CYAN}▶ Restarting Flask deployment to pull latest image...${NC}"
    kubectl rollout restart deployment flask -n "${APP_NAMESPACE}"
    
    echo -e "${CYAN}▶ Waiting for rollout to complete...${NC}"
    kubectl rollout status deployment/flask -n "${APP_NAMESPACE}" --timeout=3m
    
    cd ..
else
    echo -e "${RED}❌ Error: Directory '${K8S_DIR}' not found. Please ensure your Kubernetes manifests are in a 'kubernetes/' folder.${NC}"
    exit 1
fi

echo -e "${CYAN}▶ Current pods:${NC}"
kubectl get pods -n "${APP_NAMESPACE}"

echo -e "\n${CYAN}▶ Describing the latest pod (fetching events):${NC}"
POD_NAME=$(kubectl get pods -n "${APP_NAMESPACE}" -l app=flask -o jsonpath="{.items[0].metadata.name}")
kubectl describe pod "${POD_NAME}" -n "${APP_NAMESPACE}" | head -n 15
echo "... (output truncated for brevity) ..."

prompt_continue

# -------------------------------------------------------------------------
# PHASE 6 — Verify Database Connection
# -------------------------------------------------------------------------
section "PHASE 6: Verifying Database Connection inside Pod"

echo -e "${CYAN}▶ Checking environment variables:${NC}"
kubectl exec -it deploy/flask -n "${APP_NAMESPACE}" -- env | grep "DB_"

echo -e "\n${CYAN}▶ Checking /ready endpoint inside the pod:${NC}"
kubectl exec -n flask "${POD_NAME}" -- python -c "
import urllib.request
print(urllib.request.urlopen('http://127.0.0.1:5000/ready').read().decode())
"
echo -e "\n${CYAN}▶ Checking /health endpoint inside the pod:${NC}"
kubectl exec -n flask "${POD_NAME}" -- python -c "
import urllib.request
print(urllib.request.urlopen('http://127.0.0.1:5000/health').read().decode())
"

# -------------------------------------------------------------------------
# Final Summary
# -------------------------------------------------------------------------
section "✅ DEPLOYMENT COMPLETE"
echo -e "${GREEN}Your application has been built, pushed to ECR, and rolled out to EKS.${NC}"
echo -e "${CYAN}To see the full application logs:${NC}"
echo "  kubectl logs -n ${APP_NAMESPACE} deployment/flask"
echo -e "\n${CYAN}To check the Load Balancer ingress:${NC}"
echo "  kubectl get ingress -n ${APP_NAMESPACE}"
echo -e "\n${BOLD}${GREEN}Happy coding! 🚀${NC}"
