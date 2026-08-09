#!/bin/bash

# =============================================================================
# AWS Resource Discovery Script
# Purpose: Discover and display all AWS resources in a fancy table format
# Idempotent: Safe to run multiple times
# Dependencies: aws CLI, jq
# =============================================================================

set -euo pipefail

# Colors and formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Table characters
readonly HORIZONTAL='─'
readonly VERTICAL='│'
readonly TOP_LEFT='┌'
readonly TOP_RIGHT='┐'
readonly BOTTOM_LEFT='└'
readonly BOTTOM_RIGHT='┘'
readonly CROSS='┼'
readonly T_DOWN='┬'
readonly T_UP='┴'
readonly T_LEFT='├'
readonly T_RIGHT='┤'

# Configuration
readonly AWS_REGION="ap-south-1"
readonly PROJECT_TAG="secure-eks-platform"  # Adjust based on your project tags
readonly OWNER_TAG="shaurya-security"  # Optional: filter by owner tag

# Global arrays for table data
declare -a RESOURCE_NAMES=()
declare -a RESOURCE_TYPES=()
declare -a RESOURCE_STATUS=()
declare -a RESOURCE_DETAILS=()

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

check_dependencies() {
    local missing=()
    
    if ! command -v aws &> /dev/null; then
        missing+=("aws-cli")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    log_success "All dependencies available"
}

# =============================================================================
# Table Drawing Functions
# =============================================================================

calculate_column_widths() {
    local max_name=10 max_type=10 max_status=10 max_detail=10
    
    for i in "${!RESOURCE_NAMES[@]}"; do
        [[ ${#RESOURCE_NAMES[i]} -gt $max_name ]] && max_name=${#RESOURCE_NAMES[i]}
        [[ ${#RESOURCE_TYPES[i]} -gt $max_type ]] && max_type=${#RESOURCE_TYPES[i]}
        [[ ${#RESOURCE_STATUS[i]} -gt $max_status ]] && max_status=${#RESOURCE_STATUS[i]}
        [[ ${#RESOURCE_DETAILS[i]} -gt $max_detail ]] && max_detail=${#RESOURCE_DETAILS[i]}
    done
    
    # Ensure minimum widths
    [[ $max_name -lt 10 ]] && max_name=10
    [[ $max_type -lt 10 ]] && max_type=10
    [[ $max_status -lt 10 ]] && max_status=10
    [[ $max_detail -lt 10 ]] && max_detail=10
    
    echo "$max_name $max_type $max_status $max_detail"
}

print_separator() {
    local cols=($(calculate_column_widths))
    local name_w=${cols[0]}
    local type_w=${cols[1]}
    local status_w=${cols[2]}
    local detail_w=${cols[3]}
    
    local total_width=$((name_w + type_w + status_w + detail_w + 9))
    
    echo -ne "${CYAN}"
    echo -n "$TOP_LEFT"
    for ((i=0; i<name_w+2; i++)); do echo -n "$HORIZONTAL"; done
    echo -n "$T_DOWN"
    for ((i=0; i<type_w+2; i++)); do echo -n "$HORIZONTAL"; done
    echo -n "$T_DOWN"
    for ((i=0; i<status_w+2; i++)); do echo -n "$HORIZONTAL"; done
    echo -n "$T_DOWN"
    for ((i=0; i<detail_w+2; i++)); do echo -n "$HORIZONTAL"; done
    echo "$TOP_RIGHT"
    echo -ne "${NC}"
}

print_header() {
    local cols=($(calculate_column_widths))
    local name_w=${cols[0]}
    local type_w=${cols[1]}
    local status_w=${cols[2]}
    local detail_w=${cols[3]}
    
    echo -ne "${WHITE}${BOLD}"
    printf " ${VERTICAL} %-${name_w}s ${VERTICAL} %-${type_w}s ${VERTICAL} %-${status_w}s ${VERTICAL} %-${detail_w}s ${VERTICAL}\n" \
        "RESOURCE" "TYPE" "STATUS" "DETAILS"
    echo -ne "${NC}"
    
    # Separator after header
    echo -ne "${CYAN}"
    echo -n "$T_LEFT"
    for ((i=0; i<name_w+2; i++)); do echo -n "$HORIZONTAL"; done
    echo -n "$CROSS"
    for ((i=0; i<type_w+2; i++)); do echo -n "$HORIZONTAL"; done
    echo -n "$CROSS"
    for ((i=0; i<status_w+2; i++)); do echo -n "$HORIZONTAL"; done
    echo -n "$CROSS"
    for ((i=0; i<detail_w+2; i++)); do echo -n "$HORIZONTAL"; done
    echo "$T_RIGHT"
    echo -ne "${NC}"
}

print_row() {
    local name="$1"
    local type="$2"
    local status="$3"
    local detail="$4"
    
    local cols=($(calculate_column_widths))
    local name_w=${cols[0]}
    local type_w=${cols[1]}
    local status_w=${cols[2]}
    local detail_w=${cols[3]}
    
    # Truncate if needed
    [[ ${#name} -gt $name_w ]] && name="${name:0:$((name_w-3))}..."
    [[ ${#type} -gt $type_w ]] && type="${type:0:$((type_w-3))}..."
    [[ ${#status} -gt $status_w ]] && status="${status:0:$((status_w-3))}..."
    [[ ${#detail} -gt $detail_w ]] && detail="${detail:0:$((detail_w-3))}..."
    
    # Color status
    local status_color="${NC}"
    case "$status" in
        *active*|*Available*|*Running*|*Healthy*|*Synced*|*CREATE_COMPLETE*)
            status_color="${GREEN}"
            ;;
        *creating*|*pending*|*modifying*|*updating*)
            status_color="${YELLOW}"
            ;;
        *failed*|*error*|*deleting*|*unhealthy*)
            status_color="${RED}"
            ;;
        *)
            status_color="${BLUE}"
            ;;
    esac
    
    echo -ne "${WHITE}"
    printf " ${VERTICAL} %-${name_w}s ${VERTICAL} %-${type_w}s ${VERTICAL} " \
        "$name" "$type"
    echo -ne "${status_color}"
    printf "%-${status_w}s" "$status"
    echo -ne "${WHITE}"
    printf " ${VERTICAL} %-${detail_w}s ${VERTICAL}\n" "$detail"
    echo -ne "${NC}"
}

print_footer() {
    local cols=($(calculate_column_widths))
    local name_w=${cols[0]}
    local type_w=${cols[1]}
    local status_w=${cols[2]}
    local detail_w=${cols[3]}
    
    echo -ne "${CYAN}"
    echo -n "$BOTTOM_LEFT"
    for ((i=0; i<name_w+2; i++)); do echo -n "$HORIZONTAL"; done
    echo -n "$T_UP"
    for ((i=0; i<type_w+2; i++)); do echo -n "$HORIZONTAL"; done
    echo -n "$T_UP"
    for ((i=0; i<status_w+2; i++)); do echo -n "$HORIZONTAL"; done
    echo -n "$T_UP"
    for ((i=0; i<detail_w+2; i++)); do echo -n "$HORIZONTAL"; done
    echo "$BOTTOM_RIGHT"
    echo -ne "${NC}"
}

print_table() {
    echo ""
    log_info "AWS Resources Summary (Region: $AWS_REGION)"
    echo ""
    
    if [ ${#RESOURCE_NAMES[@]} -eq 0 ]; then
        log_warning "No resources found matching the criteria"
        return
    fi
    
    print_separator
    print_header
    for i in "${!RESOURCE_NAMES[@]}"; do
        print_row "${RESOURCE_NAMES[i]}" "${RESOURCE_TYPES[i]}" "${RESOURCE_STATUS[i]}" "${RESOURCE_DETAILS[i]}"
    done
    print_footer
    
    echo ""
    log_success "Total resources discovered: ${#RESOURCE_NAMES[@]}"
    echo ""
}

# =============================================================================
# Resource Discovery Functions
# =============================================================================

add_resource() {
    local name="$1"
    local type="$2"
    local status="$3"
    local detail="$4"
    
    # Skip if resource name is empty
    [[ -z "$name" ]] && return
    
    RESOURCE_NAMES+=("$name")
    RESOURCE_TYPES+=("$type")
    RESOURCE_STATUS+=("$status")
    RESOURCE_DETAILS+=("$detail")
}

discover_vpc() {
    log_info "Discovering VPC resources..."
    
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=*flask*" "Name=tag:project,Values=$PROJECT_TAG" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then
        local cidr=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" \
            --query 'Vpcs[0].CidrBlock' --output text)
        local state=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" \
            --query 'Vpcs[0].State' --output text)
        add_resource "$vpc_id" "VPC" "$state" "CIDR: $cidr"
        
        # Subnets
        local subnets=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' \
            --output text)
        
        while IFS=$'\t' read -r subnet_id az cidr; do
            [[ -z "$subnet_id" ]] && continue
            local type="Subnet"
            [[ "$cidr" == *"public"* ]] && type="Public Subnet"
            [[ "$cidr" == *"private"* ]] && type="Private Subnet"
            add_resource "$subnet_id" "$type" "Available" "AZ: $az, CIDR: $cidr"
        done <<< "$subnets"
        
        # Internet Gateway
        local igw_id=$(aws ec2 describe-internet-gateways \
            --filters "Name=attachment.vpc-id,Values=$vpc_id" \
            --query 'InternetGateways[0].InternetGatewayId' \
            --output text 2>/dev/null || echo "")
        if [[ -n "$igw_id" && "$igw_id" != "None" ]]; then
            add_resource "$igw_id" "Internet Gateway" "Attached" "VPC: $vpc_id"
        fi
        
        # NAT Gateway
        local nat_id=$(aws ec2 describe-nat-gateways \
            --filter "Name=vpc-id,Values=$vpc_id" \
            --query 'NatGateways[0].NatGatewayId' \
            --output text 2>/dev/null || echo "")
        if [[ -n "$nat_id" && "$nat_id" != "None" ]]; then
            local nat_state=$(aws ec2 describe-nat-gateways \
                --nat-gateway-ids "$nat_id" \
                --query 'NatGateways[0].State' --output text)
            add_resource "$nat_id" "NAT Gateway" "$nat_state" "VPC: $vpc_id"
        fi
    fi
}

discover_eks() {
    log_info "Discovering EKS resources..."
    
    local clusters=$(aws eks list-clusters \
        --region "$AWS_REGION" \
        --query 'clusters' \
        --output text 2>/dev/null || echo "")
    
    for cluster in $clusters; do
        local status=$(aws eks describe-cluster \
            --name "$cluster" \
            --region "$AWS_REGION" \
            --query 'cluster.status' \
            --output text)
        
        local version=$(aws eks describe-cluster \
            --name "$cluster" \
            --region "$AWS_REGION" \
            --query 'cluster.version' \
            --output text)
        
        add_resource "$cluster" "EKS Cluster" "$status" "v$version"
        
        # Node Groups
        local nodegroups=$(aws eks list-nodegroups \
            --cluster-name "$cluster" \
            --region "$AWS_REGION" \
            --query 'nodegroups' \
            --output text 2>/dev/null || echo "")
        
        for ng in $nodegroups; do
            local ng_status=$(aws eks describe-nodegroup \
                --cluster-name "$cluster" \
                --nodegroup-name "$ng" \
                --region "$AWS_REGION" \
                --query 'nodegroup.status' \
                --output text)
            
            local ng_instances=$(aws eks describe-nodegroup \
                --cluster-name "$cluster" \
                --nodegroup-name "$ng" \
                --region "$AWS_REGION" \
                --query 'nodegroup.scalingConfig.desiredSize' \
                --output text)
            
            add_resource "$ng" "Node Group" "$ng_status" "Cluster: $cluster, Size: $ng_instances"
        done
    done
}

discover_rds() {
    log_info "Discovering RDS resources..."
    
    local dbs=$(aws rds describe-db-instances \
        --region "$AWS_REGION" \
        --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus,Engine,DBInstanceClass,Endpoint.Address]' \
        --output text 2>/dev/null || echo "")
    
    while IFS=$'\t' read -r db_id status engine class endpoint; do
        [[ -z "$db_id" ]] && continue
        # Filter for our project (if tagged)
        add_resource "$db_id" "RDS PostgreSQL" "$status" "$engine, $class, $endpoint"
    done <<< "$dbs"
}

discover_secrets_manager() {
    log_info "Discovering Secrets Manager resources..."
    
    local secrets=$(aws secretsmanager list-secrets \
        --region "$AWS_REGION" \
        --query 'SecretList[*].[Name,ARN,LastChangedDate]' \
        --output text 2>/dev/null || echo "")
    
    while IFS=$'\t' read -r name arn last_changed; do
        [[ -z "$name" ]] && continue
        add_resource "$name" "Secret Manager" "Active" "Last changed: ${last_changed:-N/A}"
    done <<< "$secrets"
}

discover_ecr() {
    log_info "Discovering ECR repositories..."
    
    local repos=$(aws ecr describe-repositories \
        --region "$AWS_REGION" \
        --query 'repositories[*].[repositoryName,repositoryUri,createdAt]' \
        --output text 2>/dev/null || echo "")
    
    while IFS=$'\t' read -r name uri created; do
        [[ -z "$name" ]] && continue
        add_resource "$name" "ECR Repository" "Active" "URI: $uri"
    done <<< "$repos"
}

discover_kms() {
    log_info "Discovering KMS keys..."
    
    local keys=$(aws kms list-keys \
        --region "$AWS_REGION" \
        --query 'Keys[*].KeyId' \
        --output text 2>/dev/null || echo "")
    
    for key_id in $keys; do
        local state=$(aws kms describe-key \
            --key-id "$key_id" \
            --region "$AWS_REGION" \
            --query 'KeyMetadata.KeyState' \
            --output text 2>/dev/null || echo "Unknown")
        
        local desc=$(aws kms describe-key \
            --key-id "$key_id" \
            --region "$AWS_REGION" \
            --query 'KeyMetadata.Description' \
            --output text 2>/dev/null || echo "")
        
        # Filter for our keys
        if [[ "$desc" == *"flask"* ]] || [[ "$desc" == *"eks"* ]] || [[ "$desc" == *"secrets"* ]]; then
            add_resource "$key_id" "KMS Key" "$state" "$desc"
        fi
    done
}

discover_iam() {
    log_info "Discovering IAM resources..."
    
    # Roles
    local roles=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, 'flask') || contains(RoleName, 'eks') || contains(RoleName, 'alb')].[RoleName,CreateDate]" \
        --output text 2>/dev/null || echo "")
    
    while IFS=$'\t' read -r role_name created; do
        [[ -z "$role_name" ]] && continue
        add_resource "$role_name" "IAM Role" "Active" "Created: ${created:-N/A}"
    done <<< "$roles"
    
    # Policies (custom policies)
    local policies=$(aws iam list-policies \
        --scope Local \
        --query "Policies[?contains(PolicyName, 'flask') || contains(PolicyName, 'eks')].[PolicyName,IsAttachable]" \
        --output text 2>/dev/null || echo "")
    
    while IFS=$'\t' read -r policy_name attachable; do
        [[ -z "$policy_name" ]] && continue
        add_resource "$policy_name" "IAM Policy" "Active" "${attachable:-Not attached}"
    done <<< "$policies"
}

discover_load_balancer() {
    log_info "Discovering Load Balancers..."
    
    local lbs=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[*].[LoadBalancerName,DNSName,State.Code,Scheme,Type]' \
        --output text 2>/dev/null || echo "")
    
    while IFS=$'\t' read -r lb_name dns state scheme type; do
        [[ -z "$lb_name" ]] && continue
        add_resource "$lb_name" "ALB" "$state" "${scheme:-public}, $type, $dns"
    done <<< "$lbs"
}

discover_route53() {
    log_info "Discovering Route53 zones..."
    
    local zones=$(aws route53 list-hosted-zones \
        --query 'HostedZones[*].[Name,Id,Config.PrivateZone]' \
        --output text 2>/dev/null || echo "")
    
    while IFS=$'\t' read -r zone_name zone_id private; do
        [[ -z "$zone_name" ]] && continue
        local type="Hosted Zone"
        [[ "$private" == "True" ]] && type="Private Hosted Zone"
        add_resource "$zone_name" "$type" "Active" "ID: $zone_id"
    done <<< "$zones"
}

discover_s3() {
    log_info "Discovering S3 buckets..."
    
    local buckets=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, 'flask') || contains(Name, 'eks') || contains(Name, 'terraform')].[Name,CreationDate]" \
        --output text 2>/dev/null || echo "")
    
    while IFS=$'\t' read -r bucket_name created; do
        [[ -z "$bucket_name" ]] && continue
        
        # Get bucket region
        local region=$(aws s3api get-bucket-location \
            --bucket "$bucket_name" \
            --query 'LocationConstraint' \
            --output text 2>/dev/null || echo "Unknown")
        
        add_resource "$bucket_name" "S3 Bucket" "Active" "Region: ${region:-us-east-1}, Created: ${created:-N/A}"
    done <<< "$buckets"
}

discover_ec2() {
    log_info "Discovering EC2 instances (EKS nodes)..."

    local instances=$(aws ec2 describe-instances \
        --filters "Name=tag:aws:eks:cluster-name,Values=*" \
        --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,PublicIpAddress,PrivateIpAddress]' \
        --output text 2>/dev/null || echo "")
    
    while IFS=$'\t' read -r instance_id state type public_ip private_ip; do
        [[ -z "$instance_id" ]] && continue
        local detail="Type: $type"
        [[ -n "$public_ip" ]] && detail="$detail, Public: $public_ip"
        [[ -n "$private_ip" ]] && detail="$detail, Private: $private_ip"
        add_resource "$instance_id" "EC2 Instance" "$state" "$detail"
    done <<< "$instances"
}

discover_security_groups() {
    log_info "Discovering Security Groups..."
    
    local sgs=$(aws ec2 describe-security-groups \
        --filters "Name=tag:project,Values=$PROJECT_TAG" \
        --query 'SecurityGroups[*].[GroupId,GroupName,Description]' \
        --output text 2>/dev/null || echo "")
    
    while IFS=$'\t' read -r sg_id sg_name desc; do
        [[ -z "$sg_id" ]] && continue
        add_resource "$sg_id" "Security Group" "Active" "$sg_name: ${desc:0:30}"
    done <<< "$sgs"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo ""
    log_info "Starting AWS Resource Discovery..."
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Discover all resources
    discover_vpc
    discover_eks
    discover_rds
    discover_secrets_manager
    discover_ecr
    discover_kms
    discover_iam
    discover_load_balancer
    discover_route53
    discover_s3
    discover_ec2
    discover_security_groups
    
    # Print the table
    print_table
    
    # Export to JSON for potential automation
    if [ ${#RESOURCE_NAMES[@]} -gt 0 ]; then
        local json_output="["
        for i in "${!RESOURCE_NAMES[@]}"; do
            if [ $i -gt 0 ]; then
                json_output+=","
            fi
            json_output+="{\"name\":\"${RESOURCE_NAMES[i]}\",\"type\":\"${RESOURCE_TYPES[i]}\",\"status\":\"${RESOURCE_STATUS[i]}\",\"details\":\"${RESOURCE_DETAILS[i]}\"}"
        done
        json_output+="]"
        echo "$json_output" | jq '.' > aws_resources_$(date +%Y%m%d_%H%M%S).json 2>/dev/null || true
        log_info "Resource list exported to JSON"
    fi
}

# Run main function
main "$@"
