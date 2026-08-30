# Secure EKS Platform — Interview Notes

Extracted from the project build log. Covers architecture decisions, real problems hit during the build, how each was diagnosed and fixed, and the reasoning behind scope choices. Written so it can be reviewed quickly before a technical interview.

---

## 1. Project Story (Evolution)

| Version | Focus | Highlights |
|---|---|---|
| v0 | AWS CLI infra | VPC, EC2, Bastion-as-NAT, SSH admin, CloudTrail + VPC Flow Logs → Wazuh |
| v1 | Terraform foundation | Same architecture rebuilt as code, still Bastion-as-NAT/SSH |
| v2 | Secure Terraform networking | Managed NAT Gateway, SSM admin, remote state, GitHub Actions CI, Checkov |
| v3 | Containerized platform (ECS) | Docker, ECS Fargate, ECR, ALB, CloudWatch, OIDC-based GitHub Actions CI/CD |
| v4 | **Secure EKS Platform** (this project) | Kubernetes (EKS), Terraform, IRSA, External Secrets, RDS, ALB Controller, KMS |

**Key positioning decision:** rather than building EKS from scratch, the plan was to **use a trusted community module as the infrastructure base (`terraform-aws-modules/eks/aws`) and build the platform engineering on top of it** — CI/CD, security, secrets, ingress, database integration. Rationale: junior/entry-level DevOps work is rarely "build a cluster from zero," it's "extend, secure, and operate an existing cluster." Writing raw `aws_eks_cluster`/node group/OIDC resources by hand was explicitly rejected as low-value, heavily-boilerplate work that mature modules already solve well.

**Scope discipline decision:** an early draft feature list (Route53, ACM, IRSA, ESO, Secrets Manager, least-privilege IAM, Checkov, VPC Endpoints, Container Insights, Metrics Server, ConfigMaps, Security Groups...) was deliberately trimmed. Reasoning: a portfolio project that tries to demonstrate every AWS/Kubernetes feature becomes unreviewable and undefendable in an interview. Final scope was fixed at **~10-12 meaningful technologies** telling one coherent story: *"deploy a secure containerized app on EKS with Terraform, CI/CD, HTTPS, managed secrets, and a production database."* SIEM/detection engineering was deliberately split into a **separate future project** rather than bolted on, since it answers a different question ("can you detect/respond to attacks?" vs "can you build/operate a platform?").

**Things intentionally deferred/excluded:** Istio, service mesh, multi-cluster, Karpenter, spot node groups, cross-account networking, Prometheus/Grafana, HPA/Metrics Server (until later), VPC Endpoints, Cluster Autoscaler — all consciously cut to keep the project explainable end-to-end.

---

## 2. Core Architecture Decisions

### 2.1 Base module selection
- Used `terraform-aws-modules/eks/aws` and `terraform-aws-modules/vpc/aws` as the base instead of cloning a full reference repo (the module repo itself was "massive — cloning is out of option"). Decision: **reference the module via `source =`, not clone the source.**
- Justification for avoiding random community EKS repos: outdated Kubernetes versions, deprecated APIs, poor IAM practices, no maintenance.

### 2.2 Networking
- VPC: single `/16`, 2 AZs (not 3) — cheaper for a portfolio project, still demonstrates HA.
- Single NAT Gateway (`single_nat_gateway = true`) — cost optimization over one-NAT-per-AZ.
- Dedicated subnet tiers planned up front: public (ALB), private (EKS nodes), and **database subnets pre-created early** even before RDS was added, specifically to avoid re-touching the VPC later.
- Public/private subnet tags (`kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`) required for the AWS Load Balancer Controller to auto-discover subnets.

### 2.3 EKS / compute
- Node instance type changed from `t3.medium` → `t3.small`/`t3.micro` after discovering `t3.medium` wasn't within AWS Free Tier — a cost-driven mid-build correction.
- Cluster addons kept to essentials: `coredns`, `kube-proxy`, `vpc-cni`, `aws-ebs-csi-driver`.
- Kubernetes version hardcoding caught as an anti-pattern early: recommendation was to externalize `cluster_version` into `variables.tf` so upgrades become a one-line change (mirrors real-world upgrade tickets like "bump 1.30 → 1.31").
- An attempted `cluster_version = "1.34"` failed because that version didn't exist yet on EKS at the time — version numbers must match what AWS actually supports, not just what's "latest" upstream.

### 2.4 No Terraform-managed ALB
- **Decision: do not create an `aws_lb` resource in Terraform at all.** The AWS Load Balancer Controller provisions the ALB, target groups, listeners, and rules dynamically from Kubernetes `Ingress` objects. Kubernetes becomes the source of truth for the ALB, not Terraform. `alb.tf` was intentionally left empty/documentation-only.

### 2.5 IRSA pattern (used repeatedly)
Every cluster-level controller (ALB Controller, External Secrets Operator, EBS CSI Driver) followed the same IRSA pattern:
1. `terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks` creates the role scoped to a specific `namespace:service-account`.
2. Helm chart installs the controller, referencing the IRSA role ARN via a `serviceAccount.annotations.eks\.amazonaws\.com/role-arn` Helm `set`.
3. `depends_on` ties the Helm release to the IRSA module so ordering is correct.

### 2.6 Secrets strategy
- RDS module's `manage_master_user_password = true` was used so **AWS automatically creates and owns the Secrets Manager secret** — a deliberate decision *not* to hand-create a duplicate `aws_secretsmanager_secret`.
- External Secrets Operator (ESO) was chosen over manually created Kubernetes `Secret` manifests in Git, specifically to avoid committing secrets and to demonstrate a production-grade secret-management pattern that pairs naturally with IRSA.
- Split of responsibility: **Secret → username/password only** (that's all AWS's managed RDS secret contains), **ConfigMap → host/port/dbname** (values that aren't secret and aren't present in the managed secret).

### 2.7 Encryption
- ECR started on `AES256`, later upgraded to a **customer-managed KMS key (CMK)** — judged "low effort, high value" for a project positioned as "secure." One CMK was reused for ECR rather than creating per-service keys, since separate keys only add value when demonstrating key isolation specifically.

### 2.8 GitHub OIDC / CI-CD IAM (carried over + hardened from the ECS project)
- Reused ~90% of the prior ECS project's OIDC design: `aws_iam_openid_connect_provider`, hand-written trust policy (not the official IAM module), least-privilege statements per action group.
- EKS-specific additions on top of the ECS pattern: `aws_eks_access_entry` + `aws_eks_access_policy_association` (`AmazonEKSClusterAdminPolicy` initially, meant to be narrowed later) so the GitHub Actions role can actually operate against the cluster, plus `eks:DescribeCluster` permission (needed for `aws eks update-kubeconfig`).
- Deliberately kept the **hand-written trust policy** over the official Terraform IAM OIDC module, because the hand-written version already encoded a real production fix (see incident 3.1 below) that the module's defaults don't handle.

### 2.9 Terraform state split (bootstrap → 01_core → 02_platform)
This was the single biggest architectural pivot in the project (see incident 3.3). Final structure:
```
terraform/
├── bootstrap/     # S3 remote-state bucket (one-time)
├── 01_core/       # AWS-only infra: VPC, EKS, ECR, KMS, RDS, IAM, GitHub OIDC
└── 02_platform/   # Kubernetes-dependent infra: ALB Controller, External Secrets, EBS CSI
```
- `01_core` and `02_platform` use **separate state files** in the same S3 bucket (different `key`).
- `02_platform` reads `01_core`'s outputs via `data "terraform_remote_state"` instead of referencing `module.eks` directly — this removes the circular bootstrap dependency entirely (see 3.3).
- Rule of thumb established: **01_core owns AWS resources and exports only what 02_platform actually needs** (cluster name/endpoint/CA data, OIDC provider ARN, VPC ID, ECR URL, DB endpoint/secret ARN, GitHub Actions role ARN) — not everything available.
- `alb.tf` was moved from `01_core` to `02_platform` after the ALB-is-not-Terraform-managed realization, since it's cluster/platform-level, not AWS-core-level.
- EBS CSI Driver was debated (core vs platform) and settled in **02_platform**, since it's "cluster platform," matching the split's intent.

### 2.10 Dependency/version pinning philosophy
After hitting several provider-version-driven errors, the project moved from `~>` (pessimistic) constraints to **exact-pinned (`=`) versions** across Terraform core, AWS/Kubernetes/Helm providers, and every module (EKS, VPC, IAM, RDS). Explicit stated goal: **"treat this repository like production code" — reproducibility over always-latest.** `.terraform.lock.hcl` committed to git; `terraform init -upgrade` banned except when intentionally upgrading.

### 2.11 Application design decision
The Flask app for v4 was deliberately **not** a copy of the earlier ECS project's app. It was rebuilt to actively prove the platform works: `/health`, `/ready` (checks live PostgreSQL connectivity), `/metrics` (pod/node/uptime/db-latency JSON), and a dashboard UI surfacing cluster name, namespace, pod, node, secrets source, IRSA/OIDC status, DB connection status/latency, and which AWS resources back the deployment. Rationale: a generic "Hello World" doesn't demonstrate IRSA, External Secrets, or RDS connectivity to a reviewer — a self-reporting dashboard does.

---

## 3. Incidents — Problems Hit and How They Were Fixed

Each of these is a good "tell me about a time you debugged a production-style issue" answer.

### 3.1 GitHub OIDC trust policy: `sub` claim mismatch (carried in from the earlier ECS project, reapplied here)
- **Symptom:** `Error: Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity`, despite a syntactically correct trust policy.
- **Investigation:** Added a workflow step to decode the OIDC JWT payload (`curl` the token endpoint, `jq` decode the base64 payload). Found GitHub injects **internal numeric IDs** into the `sub` claim: `repo:owner@277283673/repo@1323100445:ref:refs/heads/main` — not the clean human-readable string the trust policy's `StringEquals` check expected.
- **First attempted fix (failed):** drop the `sub` condition entirely and match only on the `repository` claim → AWS rejected this with `MalformedPolicyDocument`, because **AWS IAM mandates that a GitHub OIDC trust policy evaluate either `sub` or `job_workflow_ref`** — this exists specifically to prevent overly-open cross-tenant trust relationships.
- **Final fix:** keep `sub` but use `StringLike` with a wildcard (`repo:${owner}*/*:ref:refs/heads/main`) to tolerate the injected numeric IDs, **combined with** an exact `StringEquals` check on `token.actions.githubusercontent.com:repository` for real precision (defense in depth: loose-but-required condition + a separate strict condition).
- **Takeaway used repeatedly:** decoding the OIDC token inside the workflow is the fastest way to debug claim-level trust-policy failures; this incident was preserved as a docs entry (`docs/incidents/oidc-sub-claim-mismatch.md`) and directly informed why the EKS project's `github_oidc.tf` was hand-written instead of relying on the official IAM module's defaults.

### 3.2 Terraform "chicken-and-egg" bootstrap failure (Kubernetes/Helm providers vs. `module.eks`)
- **Symptom:** `Error: reading EKS Cluster (secure-eks-cluster): couldn't find resource`, triggered by `data "aws_eks_cluster" "this"` inside `provider.tf`.
- **Root cause:** the `kubernetes`/`helm` providers were configured against `data.aws_eks_cluster.this`, which requires the cluster to already exist — but that same `terraform apply` was also trying to *create* the cluster in the same state/plan. Terraform's provider configuration is evaluated before resources are necessarily created, so the provider was "waiting" on a cluster the same apply hadn't created yet. Classic bootstrap ordering problem.
- **Immediate workaround discussed:** temporarily comment out the `kubernetes`/`helm` providers and the Helm releases, apply just the AWS resources first, then uncomment and apply again.
- **Permanent fix (the real decision):** split the codebase into **`01_core`** (pure AWS resources, no Kubernetes/Helm provider) and **`02_platform`** (Kubernetes/Helm-dependent resources), with `02_platform` consuming `01_core`'s outputs via `terraform_remote_state` instead of `module.eks` directly. This is the standard pattern used by many production Terraform codebases specifically to avoid this dependency cycle.
- Resulted in a multi-pass cleanup of stale references across `provider.tf`, `ingress.tf`, `secrets.tf`, and both IRSA modules — every `module.eks.oidc_provider_arn` / `data.aws_eks_cluster.this...` reference had to be swapped for `data.terraform_remote_state.core.outputs...`, and stale `depends_on = [module.eks, ...]` entries removed since `module.eks` no longer exists in the platform state.

### 3.3 Helm provider syntax break across major versions
- **Symptom 1:** `terraform validate` failed with `An argument named "host" is not expected here` when using Helm v2-style nested `kubernetes { ... }` block syntax against a Helm provider v3.x install.
- **Investigation:** ran `terraform providers schema -json` and inspected the schema — found that in Helm provider v3, `kubernetes` is a typed **attribute** (`kubernetes = { ... }`), not a nested **block** (`kubernetes { ... }`) as it was in v2.
- **First fix attempt:** switch to attribute syntax (`kubernetes = { host = ..., ... }`) — validated, but flagged that if it *still* failed, other causes (stale `.terraform` cache, wrong provider binary) should be suspected next.
- **Final decision:** rather than chase v3 syntax changes, **downgrade the Helm provider to the mature v2.x line** (pinned to `2.17.0`) and use the well-tested block syntax, since the project gained nothing from Helm v3-only features. This tied directly into the broader "exact-pin every provider/module version" decision (2.10) — after several of these breakages, the philosophy became: **predictability over newest-major-release** for a portfolio repo.

### 3.4 `module.*_irsa.arn` vs `.iam_role_arn`
- **Symptom:** `terraform validate` errors: `This object does not have an attribute named "arn"` for both the ALB Controller IRSA module and the External Secrets IRSA module.
- **Fix:** the `iam-role-for-service-accounts-eks` submodule exposes the role ARN as `iam_role_arn`, not `arn`. Corrected all Helm `set` blocks referencing IRSA role ARNs. Reinforced the value of running `terraform validate` before `plan`/`apply` to catch attribute-name mistakes early.

### 3.5 `ExternalSecret` requesting fields that don't exist in the source secret
- **Symptom:** `ExternalSecret` status `SecretSyncedError`; event log: `error processing spec.data[2]..., err: key host does not exist in secret ...`.
- **Investigation:** inspected the actual AWS-managed RDS secret directly with `aws secretsmanager get-secret-value` — confirmed it contains **only `username` and `password`**, not `host`/`port`/`dbname` as had been assumed.
- **Fix:** trimmed the `ExternalSecret`'s `data` list to only request `username` and `password`; moved `host`/`port`/`dbname` into the Kubernetes `ConfigMap` instead, since those values aren't secret and Terraform already knows them. This is the origin of the "Secret = credentials, ConfigMap = connection details" split noted in 2.6.

### 3.6 `ImagePullBackOff`
- **Symptom:** pods stuck in `ImagePullBackOff`; `kubectl describe pod` showed `failed to resolve reference ...:latest: not found`.
- **Investigation:** `aws ecr list-images --repository-name secure-eks-platform` returned an empty list — confirmed there was genuinely no image pushed yet.
- **Compounding issue discovered mid-fix:** attempting `docker build` failed with `open Dockerfile: no such file or directory` because the command was run from the wrong directory (`kubernetes/` instead of `app/`) — and, more fundamentally, **the `app/` directory was still completely empty** (`0 directories, 0 files`) at that point in the build. The infra and Kubernetes manifests were fully correct; the application simply hadn't been written yet.
- **Fix:** built the Flask app, then `docker build` → `docker tag` → `docker push` to ECR, then `kubectl rollout restart deployment flask -n flask` to force a fresh pull. Confirmed via `aws ecr list-images` returning the pushed tag and pods reaching `Running`.

### 3.7 Deployment/verification script issues (multiple small ones, same theme: environment assumptions)
- **Working-directory inconsistency:** an early automation script assumed different working directories at different points (root vs. `app/`), causing it to look for `.env` in the wrong place. **Fix:** resolve the script's own location once via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` and derive all paths from that, so the script behaves identically regardless of where/how it's invoked. Framed as a real automation-hygiene lesson: *"infrastructure automation should not depend on being in the right directory."*
- **Missing namespace flag:** `kubectl describe pod <name>` without `-n flask` returned `NotFound` even though the pod existed — simple namespace-scoping mistake, easy to reproduce/explain.
- **No `curl` in the runtime image:** health-check verification via `kubectl exec ... -- curl ...` failed with `executable file not found in $PATH`, because the app's base image (`python:3.13-slim`) intentionally excludes `curl` to stay minimal. **Fix:** verify readiness with Python's own `urllib.request` inside the container instead of assuming `curl` is present, or better, verify via `kubectl port-forward` / rollout status from the Kubernetes API instead of shelling into the container at all.
- **Stale kubeconfig after cluster recreation:** verification/cleanup scripts failed with `dial tcp: lookup <old-cluster-id>: no such host` because `~/.kube/config` still pointed at a destroyed cluster's endpoint. **Fix:** scripts always refresh kubeconfig at the start by reading the *current* cluster name from `terraform output` and re-running `aws eks update-kubeconfig`, rather than trusting whatever's cached locally. A `cluster_available()` helper (`kubectl cluster-info` check) was added so scripts can gracefully skip Kubernetes-side steps entirely when the cluster genuinely doesn't exist (e.g., mid-teardown), instead of hard-failing.

### 3.8 `terraform destroy` blocked: Internet Gateway won't detach (out-of-band ALB resources)
This is the most instructive incident in the whole log — a real "Terraform doesn't know what it didn't create" problem.

- **Symptom:** `terraform destroy` on `01_core` hung on `aws_internet_gateway.this[0]: Still destroying...` for 9+ minutes, then failed:
  ```
  Error: deleting EC2 Internet Gateway ...: DependencyViolation:
  Network vpc-... has some mapped public address(es). Please unmap those public address(es) before detaching the gateway.
  ```
  followed by subnet deletion also failing with `DependencyViolation: ... has dependencies and cannot be deleted`.
- **Root cause:** the **AWS Load Balancer Controller**, running inside EKS, provisions real AWS resources (ALB, listeners, target groups, security group, and — critically — **Elastic Network Interfaces placed directly in the public subnets**) *outside of Terraform's state*, because it talks to the AWS API directly from inside the cluster in response to a Kubernetes `Ingress` object. Terraform has no record of these ENIs, so when it tries to tear down the VPC/subnets/IGW, AWS blocks it because those ENIs are still attached.
- **Why it happened specifically here:** the teardown order was `02_platform` destroy → immediately `01_core` destroy, without waiting for AWS to finish asynchronously cleaning up the ALB's ENIs/security group after the `Ingress` object was removed. Kubernetes reports the Ingress as "deleted" before AWS has actually finished releasing the underlying network resources.
- **Diagnosis approach modeled:** don't guess — read the *last ~20 lines* of the destroy error for the specific dependency AWS names (mapped public IPs / ENI / dependent resource), then cross-check with targeted `aws` CLI calls: `describe-network-interfaces` (filtered by VPC ID), `describe-load-balancers`, `describe-target-groups`, `describe-addresses`, `describe-nat-gateways`, `describe-vpc-endpoints`, `describe-security-groups`, `describe-internet-gateways`.
- **Fix — correct teardown order established:**
  ```
  Ingress → TargetGroupBinding → ALB → Target Groups → ALB Security Group → ALB ENIs → THEN terraform destroy (01_core)
  ```
  Simply waiting for the `Ingress` object to disappear from `kubectl` is **not sufficient** — the script must actively poll AWS until the ALB and its ENIs are actually gone.
- **Fix — new script (`40_cleanup_platform.sh`)**: runs *before* `terraform destroy`, does, in order: `kubectl delete ingress --ignore-not-found`, then polls (`while kubectl get ingress ...`) until it's gone, then polls until no `TargetGroupBinding` remains, then polls `aws elbv2 describe-load-balancers` until the ALB name disappears, then lists any remaining `ELB *`-described ENIs (scoped to the project's VPC ID, not the whole account) as a final sanity check.
- **Reusability fix:** all cluster-interaction scripts were made resilient to the cluster not existing (see 3.7) so cleanup/verify scripts don't hard-crash mid-teardown or after a cluster has already been destroyed.
- **Interview-ready one-liner:** *"Terraform can only destroy what it manages. When a Kubernetes controller reaches out and creates AWS resources directly (like the ALB Controller does), you need an explicit out-of-band cleanup step — polling AWS itself for the ALB/ENIs to actually disappear — before you can safely tear down the VPC underneath it."*

### 3.9 Free-tier / cost correction mid-build
- Switched managed node group `instance_types` from `t3.medium` to `t3.small`/`t3.micro` after realizing `t3.medium` fell outside AWS Free Tier eligibility — a practical reminder to validate instance-type cost/eligibility before provisioning, not after.

### 3.10 Ephemeral values after every destroy/apply cycle
- Recognized that **RDS's Secrets Manager ARN changes every time the database is recreated** (new random suffix), which broke the hardcoded ARN in `ExternalSecret` on every fresh `terraform apply`.
- **Fix:** stopped hardcoding the ARN. Converted `03_externalsecret.yaml` into a `.tpl` template with `key: ${DB_SECRET_ARN}`, and had the deploy script inject the live value at apply time via `DB_SECRET_ARN="$(terraform -chdir=terraform/01_core output -raw database_secret_arn)"` piped through `envsubst`. Result: a fully idempotent redeploy with **zero manual edits** after any destroy/apply cycle. The only other ephemeral value identified was the ALB DNS name, which is expected to change and isn't something to "fix."

---

## 4. Kubernetes Deployment Sequence (as actually executed)

```
Namespace → StorageClass → SecretStore → ExternalSecret → ConfigMap
   → Deployment → verify Pods Running → Service (ClusterIP)
   → verify Endpoints/port-forward → Ingress (ALB) → verify ALB DNS
   → TargetGroupBinding healthy → (planned: ACM/HTTPS, Route53, GitHub Actions CI/CD, Trivy)
```

Deliberate rule followed throughout: **don't move to the next layer until the current one is verified.** E.g., Ingress was not created until the ClusterIP Service's Endpoints were confirmed populated with both pod IPs; GitHub Actions CI/CD was deferred until the manual `kubectl apply` path fully worked end-to-end (Service → Ingress → ALB → public curl), on the reasoning that automating a broken pipeline just automates the failure.

---

## 5. Repository / Ops Conventions Worth Mentioning

- **Numbered script/manifest naming** (`00_namespace.yaml` ... `08_hpa.yaml`, `10_platform_check.sh`, `20_apply_platform.sh`, `30_verify_platform.sh`, `40_cleanup_platform.sh`) makes execution order self-documenting.
- **Incident write-ups committed to the repo** (`docs/incidents/oidc-sub-claim-mismatch.md`) — treated as evidence of debugging skill, not just a fix.
- **Separate Terraform state per lifecycle boundary** (bootstrap / core / platform) rather than one monolithic state — reduces blast radius and avoids circular provider dependencies.
- **Exact version pinning + committed lock file** across Terraform, providers, and modules — reproducibility prioritized over "always latest."
- **Idempotent redeploy** as an explicit design goal — no manual edits should be required after a `terraform destroy` → `terraform apply` cycle.
- **Semantic versioning per-repository**, not across the whole portfolio (`v1.0.0` for this repo's first stable milestone, even though it's the "4th" project overall) — tags are meaningful within one repo's Git history, not across separate repositories.

---

## 6. Likely Interview Talking Points

- **"Walk me through your EKS platform's architecture."** → VPC (public/private/db subnets, 2 AZs, single NAT) → EKS with managed node group → IRSA-scoped controllers (ALB Controller, External Secrets, EBS CSI) → RDS Postgres with AWS-managed Secrets Manager credential → Flask app synced via ExternalSecret/ConfigMap → ALB provisioned dynamically via Ingress → GitHub OIDC for keyless CI/CD.
- **"Why not create the ALB in Terraform?"** → Because the AWS Load Balancer Controller owns ALB lifecycle from Kubernetes `Ingress` objects; Terraform-managing it too would create competing sources of truth (and does create real teardown problems — see 3.8).
- **"Describe a real production-style bug you fixed."** → The IGW/ENI destroy-order incident (3.8) is the strongest story: correctly diagnosed a resource Terraform didn't own, understood why (async AWS cleanup vs Kubernetes reporting), and built a deterministic pre-destroy cleanup script instead of guessing/retrying.
- **"How do you handle secrets?"** → Never commit them; let AWS own the RDS credential lifecycle (`manage_master_user_password`), sync into the cluster via External Secrets Operator + IRSA (no static AWS keys anywhere), split secret vs. non-secret config between `Secret` and `ConfigMap`.
- **"How do you keep Terraform reproducible?"** → Exact-pinned versions, committed lock file, split state per lifecycle stage, remote state via S3, never `-upgrade` unintentionally.
- **"How would you improve this further?"** → Tighten the RDS security group from whole-VPC CIDR to just the node/pod security group; narrow the GitHub Actions EKS access policy from cluster-admin down to least privilege; finish HTTPS (ACM + Route53) and CI/CD (Trivy scan + automated `kubectl`/Helm deploy) — both were roadmapped but not yet completed as of this log.

---

## 7. Roadmap Status at End of Log

**Done:** Terraform (bootstrap/core/platform split), VPC, EKS + managed node groups, IRSA, EBS CSI, ALB Controller, External Secrets Operator, Secrets Manager integration, KMS CMK for ECR, RDS PostgreSQL, GitHub OIDC role, ECR, Flask app with health/ready/metrics endpoints, Service, Ingress with a working public ALB (HTTP), full local build → push → rollout automation, idempotent redeploy scripting.

**Not yet done (planned):** ACM certificate + HTTPS, Route53 custom domain, GitHub Actions CI/CD pipeline (build/scan/deploy automation), Trivy image scanning integration.
