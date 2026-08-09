#!/usr/bin/env bash
set -Eeuo pipefail

GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m"

# --- Auto-detect paths based on where the script is run ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
CORE="$ROOT/terraform/01_core"

# --- Configuration ---
REGION="ap-south-1"
NAMESPACE="flask"

# --- 1. Verify Terraform outputs exist ---
if [ ! -d "$CORE" ]; then
    echo -e "${RED}[ERROR] Could not find Terraform directory at: $CORE${NC}"
    echo -e "${YELLOW}Make sure you are running this from within the 'kubernetes/' folder.${NC}"
    exit 1
fi

CLUSTER_NAME="$(terraform -chdir="$CORE" output -raw cluster_name 2>/dev/null || true)"
VPC_ID="$(terraform -chdir="$CORE" output -raw vpc_id 2>/dev/null || true)"

if [ -z "$CLUSTER_NAME" ] || [ -z "$VPC_ID" ]; then
    echo -e "${RED}[ERROR] Could not retrieve 'cluster_name' or 'vpc_id' from Terraform outputs in $CORE${NC}"
    echo -e "${YELLOW}Ensure you have run 'terraform apply' in 01_core recently.${NC}"
    exit 1
fi

# --- 2. Check if cluster exists ---
echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE} 🧹 Platform Cleanup Script${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo -e "[INFO] Updating kubeconfig for $CLUSTER_NAME..."
    aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null
else
    echo -e "${YELLOW}[WARN] Cluster '$CLUSTER_NAME' doesn't exist. Exiting.${NC}"
    exit 0
fi

# --- 3. Uninstall Helm Charts ---
echo -e "\n${BLUE}▶ Uninstalling Helm charts...${NC}"
if helm list -n kube-system 2>/dev/null | grep -q aws-load-balancer-controller; then
    echo "Uninstalling aws-load-balancer-controller..."
    helm uninstall aws-load-balancer-controller -n kube-system || true
    sleep 10 # Allow controller to terminate
fi

if helm list -n external-secrets 2>/dev/null | grep -q external-secrets; then
    echo "Uninstalling external-secrets..."
    helm uninstall external-secrets -n external-secrets || true
    sleep 5
fi

# --- 4. Delete EBS CSI Driver Addon ---
echo -e "\n${BLUE}▶ Removing EBS CSI Driver addon...${NC}"
aws eks delete-addon --cluster-name "$CLUSTER_NAME" --addon-name aws-ebs-csi-driver --region "$REGION" 2>/dev/null || true
echo "Waiting for addon deletion..."
sleep 10

# --- 5. Delete Ingress ---
echo -e "\n${BLUE}▶ Deleting Ingress...${NC}"
kubectl delete ingress flask -n "$NAMESPACE" --ignore-not-found=true

echo "Waiting for Ingress to be fully removed..."
while kubectl get ingress flask -n "$NAMESPACE" >/dev/null 2>&1; do
    sleep 5
done
echo -e "${GREEN}✓ Ingress removed${NC}"

# --- 6. Wait for TargetGroupBindings ---
echo -e "\n${BLUE}▶ Checking TargetGroupBindings...${NC}"
while kubectl get targetgroupbindings -n "$NAMESPACE" --no-headers 2>/dev/null | grep -q .; do
    echo "Waiting for TargetGroupBindings to be removed..."
    sleep 5
done
echo -e "${GREEN}✓ TargetGroupBindings removed${NC}"

# --- 7. Wait for Load Balancer (ALB) cleanup ---
echo -e "\n${BLUE}▶ Waiting for ALB deletion...${NC}"
while aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?contains(LoadBalancerName,'k8s-flask')]" --output text | grep -q k8s-flask; do
    echo "ALB still exists. Waiting..."
    sleep 10
done
echo -e "${GREEN}✓ ALB removed${NC}"

# --- 8. Wait for orphaned ENIs ---
echo -e "\n${BLUE}▶ Checking for orphaned ENIs...${NC}"
while aws ec2 describe-network-interfaces --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" "Name=description,Values=ELB" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text | grep -q eni-; do
    echo "Orphaned ENIs still attached. Waiting..."
    sleep 10
done
echo -e "${GREEN}✓ Orphaned ENIs cleaned up${NC}"

# --- 9. Clean up namespace ---
echo -e "\n${BLUE}▶ Cleaning up the '$NAMESPACE' namespace...${NC}"
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true

# --- 10. Check for leftover EBS volumes ---
echo -e "\n${BLUE}▶ Checking for leftover EBS volumes (gp3)...${NC}"
LEFT_VOLUMES=$(aws ec2 describe-volumes --region "$REGION" --filters "Name=volume-type,Values=gp3" "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" --query 'Volumes[].VolumeId' --output text)
if [ -n "$LEFT_VOLUMES" ]; then
    echo -e "${YELLOW}[WARN] Found leftover EBS volumes: $LEFT_VOLUMES${NC}"
    echo "To delete them, run: aws ec2 delete-volume --volume-id <VOL-ID>"
else
    echo -e "${GREEN}✓ No orphaned EBS volumes found.${NC}"
fi

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} 🧹 Platform Cleanup Completed Successfully ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
