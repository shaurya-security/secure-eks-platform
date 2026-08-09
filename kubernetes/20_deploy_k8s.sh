#!/usr/bin/env bash
set -Eeuo pipefail

GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m"

ROOT="$(cd "$(dirname "$0")" && pwd)"
CORE="$ROOT/../terraform/01_core"

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE} Kubernetes Deployment${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

DB_SECRET_ARN="$(terraform -chdir="$CORE" output -raw database_secret_arn)"

export DB_SECRET_ARN

echo -e "${GREEN}✓${NC} Retrieved latest RDS Secret ARN"

kubectl apply -f "$ROOT/00_namespace.yaml"

kubectl apply -f "$ROOT/01_storageclass.yaml"

kubectl apply -f "$ROOT/02_secretstore.yaml"

envsubst < "$ROOT/03_externalsecret.yaml.tpl" | kubectl apply -f -

kubectl apply -f "$ROOT/04_configmap.yaml"

kubectl apply -f "$ROOT/05_deployment.yaml"

kubectl apply -f "$ROOT/06_service.yaml"

kubectl apply -f "$ROOT/07_ingress.yaml"

kubectl apply -f "$ROOT/08_hpa.yaml"

echo
echo -e "${GREEN}✓ Kubernetes manifests applied successfully${NC}"
