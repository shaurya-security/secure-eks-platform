#!/usr/bin/env bash
set -Eeuo pipefail

GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

ROOT="$(cd "$(dirname "$0")" && pwd)"
CORE="$ROOT/../terraform/01_core"

# Ensure kubeconfig always points to current cluster
CLUSTER_NAME="$(terraform -chdir="$CORE" output -raw cluster_name)"
REGION="ap-south-1"

aws eks update-kubeconfig \
    --region "$REGION" \
    --name "$CLUSTER_NAME" >/dev/null

echo
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE} Secure EKS Platform Verification${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo
echo "Namespace"

kubectl get ns flask >/dev/null \
&& pass "Namespace exists" \
|| fail "Namespace missing"

echo
echo "External Secret"

kubectl get externalsecret -n flask postgres-secret >/dev/null \
&& pass "ExternalSecret exists" \
|| fail "ExternalSecret missing"

kubectl get secret -n flask postgres-secret >/dev/null \
&& pass "Kubernetes Secret synced" \
|| fail "Secret not synced"

echo
echo "Deployment"

kubectl rollout status deployment/flask -n flask >/dev/null \
&& pass "Deployment healthy" \
|| fail "Deployment unhealthy"

echo
echo "Pods"

kubectl get pods -n flask

READY=$(kubectl get pods -n flask \
-o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{" "}{end}')

if [[ "$READY" == *false* ]]; then
    fail "One or more pods not Ready"
else
    pass "All pods Ready"
fi

echo
echo "Service"

kubectl get svc -n flask

kubectl get endpoints -n flask >/dev/null \
&& pass "Service endpoints available" \
|| fail "No endpoints"

echo
echo "Ingress"

kubectl get ingress -n flask

ALB=$(kubectl get ingress flask -n flask \
-o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [[ -n "$ALB" ]]; then
    pass "ALB provisioned"
    echo "$ALB"
else
    fail "ALB not provisioned"
fi

echo
echo "Target Group"

kubectl get targetgroupbindings -n flask >/dev/null \
&& pass "TargetGroupBinding created" \
|| fail "Missing TargetGroupBinding"

echo
echo "Application"

if curl -fs "http://$ALB/health" >/dev/null; then
    pass "/health reachable"
else
    warn "/health failed"
fi

if curl -fs "http://$ALB/ready" >/dev/null; then
    pass "/ready reachable"
else
    warn "/ready failed"
fi

if curl -fs "http://$ALB/" >/dev/null; then
    pass "Homepage reachable"
else
    fail "Homepage unreachable"
fi

echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} Platform verification complete${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
