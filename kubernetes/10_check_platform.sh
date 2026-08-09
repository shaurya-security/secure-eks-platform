#!/usr/bin/env bash

set -euo pipefail

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

section() {
    echo
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

#############################################
# AWS CLI
#############################################

section "AWS"

aws sts get-caller-identity >/dev/null \
    && pass "AWS authentication" \
    || fail "AWS authentication"

aws eks describe-cluster \
    --region ap-south-1 \
    --name secure-eks-cluster \
    --query "cluster.status" \
    --output text | grep ACTIVE >/dev/null \
    && pass "EKS cluster ACTIVE" \
    || fail "EKS cluster"

#############################################
# kubectl
#############################################

section "kubectl"

kubectl version --client >/dev/null \
    && pass "kubectl installed" \
    || fail "kubectl missing"

kubectl cluster-info >/dev/null \
    && pass "Connected to cluster" \
    || fail "kubectl cannot reach cluster"

kubectl get nodes >/dev/null \
    && pass "Worker nodes reachable" \
    || fail "Cannot list nodes"

#############################################
# Core Addons
#############################################

section "Core Pods"

kubectl get pods -n kube-system | grep aws-load-balancer-controller >/dev/null \
    && pass "AWS Load Balancer Controller" \
    || fail "ALB Controller"

kubectl get pods -n external-secrets | grep external-secrets >/dev/null \
    && pass "External Secrets Operator" \
    || fail "External Secrets"

kubectl get pods -n kube-system | grep ebs-csi-controller >/dev/null \
    && pass "EBS CSI Driver" \
    || fail "EBS CSI Driver"

#############################################
# CRDs
#############################################

section "CRDs"

kubectl get crd secretstores.external-secrets.io >/dev/null 2>&1 \
    && pass "SecretStore CRD" \
    || fail "SecretStore CRD"

kubectl get crd externalsecrets.external-secrets.io >/dev/null 2>&1 \
    && pass "ExternalSecret CRD" \
    || fail "ExternalSecret CRD"

kubectl get crd targetgroupbindings.elbv2.k8s.aws >/dev/null 2>&1 \
    && pass "ALB CRDs" \
    || fail "ALB CRDs"

#############################################
# Storage
#############################################

section "Storage"

kubectl get storageclass >/dev/null \
    && pass "StorageClass exists" \
    || fail "No StorageClass"

kubectl get storageclass | grep "(default)" >/dev/null \
    && pass "Default StorageClass configured" \
    || warn "No default StorageClass"

#############################################
# IRSA
#############################################

section "IRSA"

kubectl get sa aws-load-balancer-controller \
    -n kube-system \
    -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' \
    | grep arn >/dev/null \
    && pass "ALB IRSA"

kubectl get sa external-secrets \
    -n external-secrets \
    -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' \
    | grep arn >/dev/null \
    && pass "External Secrets IRSA"

kubectl get sa ebs-csi-controller-sa \
    -n kube-system \
    -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' \
    | grep arn >/dev/null \
    && pass "EBS CSI IRSA"

#############################################
# AWS Resources
#############################################

section "AWS Resources"

aws ecr describe-repositories \
    --repository-names secure-eks-platform >/dev/null \
    && pass "ECR Repository"

aws rds describe-db-instances \
    --db-instance-identifier secure-eks-platform-postgres >/dev/null \
    && pass "RDS"

#############################################
# Summary
#############################################

echo
echo "Platform pre-flight completed."
