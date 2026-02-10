# First Deployment Infrastructure

This directory contains Terraform configuration for deploying multi-cloud infrastructure with Humanitec Platform Orchestrator.

## Architecture

This infrastructure uses a **provider-per-module architecture** where each cloud module contains its own Kubernetes and Helm provider configurations, as well as its own environments. This allows true multi-cloud support where you can enable multiple clouds simultaneously and choose deployment targets by environment name.

## Structure

```
├── main.tf                   # Root module with cloud module calls
├── humanitec.tf              # Shared Humanitec Platform Orchestrator resources
├── variables.tf              # Input variables
├── outputs.tf                # Common outputs (prefix, org, project)
├── destroy-order.sh          # Safe destruction script with proper ordering
└── modules/
    ├── local/                # Local KinD module (Kubernetes in Docker)
    ├── gcp/                  # GCP module (GKE + Humanitec resources + environments)
    ├── aws/                  # AWS module (EKS + Humanitec resources + environments)
    ├── azure/                # Azure module (AKS + Humanitec resources + environments)
    └── shared/
        └── runner-integration/  # Shared runner deployment logic
```

## Quick Start

### 1. Choose Your Environment(s)

Edit [main.tf](main.tf) to enable your desired environment(s):

#### Local Development (Enabled by Default)
```hcl
# Local KinD - Perfect for development without cloud costs
module "local" {
  source = "./modules/local"
  ...
}
```
**Requirements**: Docker + KinD CLI
**Access**: `http://*.localtest.me` (auto-resolves to 127.0.0.1)
**See**: [modules/local/README.md](modules/local/README.md)

#### Cloud Environments (Comment/Uncomment as Needed)
```hcl
# Enable GCP
# module "gcp" {
#   source = "./modules/gcp"
#   ...
# }

# Enable AWS
# module "aws" {
#   source = "./modules/aws"
#   ...
# }

# Enable Azure
# module "azure" {
#   source = "./modules/azure"
#   ...
# }
```

**Note**: You can enable multiple environments simultaneously!

### 2. Configure Variables

Set your variables via `terraform.tfvars` or environment variables:

```hcl
humanitec_org        = "your-org"
humanitec_auth_token = "your-token"
prefix               = "demo"  # Optional, will generate random if empty

# Cloud-specific variables (only needed for enabled clouds)
aws_region = "us-east-1"       # If using AWS
gcp_project_id = "my-project"  # If using GCP
azure_subscription_id = "..."  # If using Azure
```

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 4. Choose Your Deployment Target

Each module creates its own environments:
- **Local**: `{prefix}-local-dev`
- **AWS**: `aws-dev`, `aws-score`
- **GCP**: `gcp-dev`, `gcp-score`
- **Azure**: `azure-dev`, `azure-score`

Deploy locally by targeting `{prefix}-local-dev`, or to cloud by targeting cloud-specific environments:

```bash
# Deploy locally
hctl deploy myapp {prefix}-local-dev ./score.yaml

# Deploy to cloud
hctl deploy myapp gcp-dev ./score.yaml
```

### 5. Destroy

Use the safe destruction script:

```bash
./destroy-order.sh
```

This script ensures proper ordering: environments → Humanitec resources → infrastructure.

## Key Features

### Gateway API / HTTPRoute Support

All environments (local, GCP, AWS, Azure) come with **Envoy Gateway** pre-installed, providing native support for Kubernetes Gateway API and HTTPRoute resources. This gives you:

- ✅ **Cloud-agnostic routing** - Same HTTPRoute works everywhere
- ✅ **Advanced traffic management** - Canary deployments, header-based routing, traffic splitting
- ✅ **Modern API** - Successor to Kubernetes Ingress with typed CRDs
- ✅ **Multi-protocol** - HTTP, HTTPS, TCP, UDP, gRPC

**Example HTTPRoute**:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
spec:
  parentRefs:
    - name: default-gateway
      namespace: envoy-gateway-system
  hostnames:
    - "myapp.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-service
          port: 8080
```

### Environments-per-Cloud Architecture

Each cloud module creates its own environments (e.g., `aws-dev`, `gcp-dev`). This means:

- ✅ **Natural dependencies** - Environments depend on runners in same module
- ✅ **True multi-cloud** - Enable all three clouds simultaneously
- ✅ **Choose cloud by environment** - Deploy to `aws-dev` vs `gcp-dev` to pick cloud
- ✅ **No dependency races** - First apply always works
- ✅ **Isolated deployments** - Each cloud's environments use that cloud's runner

### Provider-per-Module Architecture

Each cloud module (GCP, AWS, Azure) contains its own `providers.tf` with Kubernetes and Helm provider configurations that connect to that cloud's cluster. This means:

- ✅ **No provider conflicts** - Each module's providers are isolated
- ✅ **Easy enabling** - Comment/uncomment modules without complex configuration
- ✅ **Independent deployment** - Modules can be enabled/disabled independently

### Shared Humanitec Resources

Cloud-agnostic Humanitec resources (providers, resource types, modules) are defined in [humanitec.tf](humanitec.tf):
- Kubernetes provider (cloud-agnostic)
- Helm provider (cloud-agnostic) 
- Ansible provider (for VM deployments)
- K8s namespace resource type and module
- In-cluster Postgres resource type and module
- Score workload resource type and modules
- Ansible score workload module (for VM-based deployments)

### Cloud-Specific Humanitec Resources

Each cloud module defines its own Humanitec resources in `humanitec-resources.tf`:
- **GCP**: GCS buckets, Pub/Sub queues, GKE service accounts, VM fleets
- **AWS**: VM fleets
- **Azure**: VM fleets

Each cloud module also defines its own module rules for `ansible_score_workload` in `environments.tf`, which triggers VM-based deployments to that cloud's `score` environment.

## Multi-Cloud Deployment

To deploy to multiple clouds:

1. **Uncomment multiple modules** in [main.tf](main.tf):
   ```hcl
   module "aws" { ... }
   module "gcp" { ... }
   module "azure" { ... }
   ```

2. **Run terraform apply** - All clouds will be provisioned

3. **Deploy to specific environment** by name:
   - `{prefix}-local-dev` → Deploys to local KinD cluster
   - `aws-dev` / `aws-score` → Deploys to AWS
   - `gcp-dev` / `gcp-score` → Deploys to GCP
   - `azure-dev` / `azure-score` → Deploys to Azure

## Module Documentation

Detailed documentation for each module:
- **[Local KinD Module](modules/local/README.md)** - Local development with KinD
- **[modules/README.md](modules/README.md)** - Cloud module structure and design
  - Module structure and design
  - Variables and outputs
  - How to add new cloud providers

## Safe Destruction

The [destroy-order.sh](destroy-order.sh) script ensures safe teardown:

1. **Destroys environments first** - Prevents Humanitec API errors
2. **Destroys Humanitec resources in order** - Module rules → Modules → Resource types
3. **Destroys remaining infrastructure** - Clusters, networks, etc.
4. **Auto-retry logic** - Waits 10 seconds and retries if resources remain

## Environment Naming Convention

Environments follow these patterns:
- **Local**: `{prefix}-local-dev` - Local KinD cluster for development
- **Cloud**: `{cloud}-{purpose}` - Cloud-specific environments
  - `aws-dev` - AWS development environment
  - `aws-score` - AWS environment for Score/VM-based workloads
  - `gcp-dev` - GCP development environment
  - `gcp-score` - GCP environment for Score/VM-based workloads
  - `azure-dev` - Azure development environment
  - `azure-score` - Azure environment for Score/VM-based workloads

## Benefits

✅ **Natural dependencies** - Environments wait for runners in same module  
✅ **No race conditions** - First apply always works  
✅ **True multi-cloud** - Enable all clouds simultaneously  
✅ **Choose cloud by env name** - Deploy to `aws-dev` vs `gcp-dev`  
✅ **Isolated modules** - Each cloud module is self-contained  
✅ **Shared logic** - Runner integration code is reused across clouds  
✅ **Safe destruction** - Proper ordering prevents API errors

## Getting Started

1. Choose your cloud provider(s) and uncomment their module(s) in [main.tf](main.tf)
2. Set your variables (see variables.tf for all options)
3. Run `terraform init && terraform plan`
4. Review the plan, then run `terraform apply`
5. Deploy to specific cloud by using the cloud-specific environment names

## Need Help?

- **Module details**: See [modules/README.md](modules/README.md)
- **Variables**: Check [variables.tf](variables.tf) for all configuration options
- **Destruction**: Review [destroy-order.sh](destroy-order.sh) for safe teardown procedure
