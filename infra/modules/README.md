# Infrastructure Modules

This directory contains Terraform modules for deploying cloud infrastructure and Humanitec Platform Orchestrator integration.

## Architecture Overview

This infrastructure uses an **environments-per-cloud architecture**. Each cloud module contains:
- Its own Kubernetes cluster
- Its own `providers.tf` with Kubernetes/Helm provider configurations
- Its own environments (e.g., `aws-dev`, `gcp-dev`)
- Its own Humanitec runner and resources

This design enables true multi-cloud support where multiple clouds can be enabled simultaneously, and you choose the deployment target by environment name.

## Module Structure

### Cloud Provider Modules

Each cloud provider has its own self-contained module:

#### [gcp/](gcp/)
Google Cloud Platform infrastructure:
- **Cluster**: GKE cluster with node pools
- **Network**: VPC, subnets, firewall rules
- **IAM**: Service accounts and workload identity
- **Namespace**: Runner namespace (`namespace.tf`)
- **CloudNativePG**: Postgres operator (`cnpg.tf`)
- **Runner**: Humanitec runner integration (`runner.tf`)
- **Providers**: GKE-specific Kubernetes/Helm providers (`providers.tf`)
- **Environments**: `gcp-dev`, `gcp-score` (`environments.tf`)
- **Humanitec Resources**: GCS buckets, Pub/Sub queues, k8s service accounts, VM fleets (`humanitec-resources.tf`)

#### [aws/](aws/)
Amazon Web Services infrastructure:
- **Cluster**: EKS cluster with node groups
- **Network**: VPC, subnets, internet gateway
- **IAM**: Roles, policies, OIDC provider, IRSA
- **Namespace**: Runner namespace (`namespace.tf`)
- **CloudNativePG**: Postgres operator (`cnpg.tf`)
- **Runner**: Humanitec runner integration (`runner.tf`)
- **Providers**: EKS-specific Kubernetes/Helm providers (`providers.tf`)
- **Environments**: `aws-dev`, `aws-score` (`environments.tf`)
- **Humanitec Resources**: VM fleets (`humanitec-resources.tf`)

#### [azure/](azure/)
Microsoft Azure infrastructure:
- **Cluster**: AKS cluster with node pools
- **Network**: Virtual Network, subnets
- **IAM**: Managed identities, federated credentials
- **Namespace**: Runner namespace (`namespace.tf`)
- **CloudNativePG**: Postgres operator (`cnpg.tf`)
- **Runner**: Humanitec runner integration (`runner.tf`)
- **Providers**: AKS-specific Kubernetes/Helm providers (`providers.tf`)
- **Environments**: `azure-dev`, `azure-score` (`environments.tf`)
- **Humanitec Resources**: VM fleets (`humanitec-resources.tf`)

### Shared Modules

#### [shared/runner-integration/](shared/runner-integration/)
Reusable module for deploying Humanitec Kubernetes Agent Runner:
- Helm chart deployment (ghcr.io/humanitec/charts/humanitec-agent)
- Platform Orchestrator runner registration
- Kubernetes RBAC setup (ServiceAccount, ClusterRoleBinding)
- Cloud-agnostic - accepts cloud-specific configuration as variables

Used by all three cloud modules to avoid code duplication.

## Key Files in Each Cloud Module

Each cloud module has a consistent structure:

```
modules/gcp/  (or aws/ or azure/)
├── main.tf                    # Core infrastructure (cluster, network)
├── providers.tf               # Kubernetes/Helm providers connecting to this cluster
├── namespace.tf               # Runner namespace creation
├── cnpg.tf                    # CloudNativePG operator deployment
├── runner.tf                  # Runner integration (calls shared module)
├── environments.tf            # Cloud-specific environments (NEW!)
├── humanitec-resources.tf     # Cloud-specific Humanitec resources
├── variables.tf               # Module inputs
├── outputs.tf                 # Module outputs
└── versions.tf                # Provider version requirements
```

## Module Design Principles

### 1. Environments-per-Cloud
Each cloud module creates its own environments (`aws-dev`, `gcp-dev`, etc.) with natural dependencies on the runner in the same module. This solves the "no matching runner found" problem permanently.

### 2. Provider Isolation
Each cloud module has its own `providers.tf` that configures Kubernetes and Helm providers to connect to that cloud's cluster. This prevents provider conflicts when multiple modules are enabled.

### 3. Self-Contained Modules
Each module is completely isolated:
- Cluster
- Network
- Runner
- **Environments** ← Key addition
- Cloud-specific Humanitec resources

### 4. No Cross-Dependencies
Cloud modules are independent of each other. You can enable AWS without having GCP or Azure code present.

### 5. Shared Logic for Common Tasks
The runner deployment logic is identical across clouds, so it lives in `shared/runner-integration/` and is called by each cloud module.

### 6. Cloud-Specific Module Rules
Each cloud module defines its own module rule for `ansible_score_workload` in `environments.tf`. This associates the ansible workload module with that cloud's `score` environment.

## Module Inputs

Each cloud module accepts similar inputs:

**Common Variables:**
- `prefix` - Resource name prefix (string)
- `humanitec_org` - Humanitec organization ID (string)
- `humanitec_auth_token` - Humanitec API token (string, sensitive)
- `public_key_pem` - TLS public key for runner auth (string)
- `private_key_pem` - TLS private key for runner auth (string, sensitive)
- `project_id` - Humanitec project ID (string) ← **NEW**
- `env_type_id` - Humanitec environment type ID (string) ← **NEW**

**Cloud-Specific Variables:**
- **GCP**: `gcp_project_id`, `gcp_region`, `gcp_zone`
- **AWS**: `aws_region`
- **Azure**: `azure_subscription_id`, `azure_tenant_id`, `azure_client_id`, `azure_client_secret`, `azure_location`

See each module's `variables.tf` for complete documentation.

## Module Outputs

Each cloud module provides outputs:

**Common Outputs:**
- `cluster_name` - Cluster name
- `cluster_endpoint` - Cluster API endpoint (sensitive)
- `runner_id` - Humanitec runner ID

**Cloud-Specific Outputs:**
- **GCP**: `service_account_email`, `network_name`
- **AWS**: `cluster_oidc_issuer_url`, `runner_role_arn`, `vpc_id`
- **Azure**: `resource_group_name`, `oidc_issuer_url`, `runner_identity_client_id`, `vnet_id`

See each module's `outputs.tf` for complete lists.

## How Modules are Called

In the root [main.tf](../main.tf), modules are called with comment-based enablement:

```hcl
# Enable AWS by uncommenting
module "aws" {
  source = "./modules/aws"
  
  prefix               = local.prefix
  aws_region           = var.aws_region
  humanitec_org        = var.humanitec_org
  humanitec_auth_token = var.humanitec_auth_token
  public_key_pem       = tls_private_key.agent_runner_key.public_key_pem
  private_key_pem      = tls_private_key.agent_runner_key.private_key_pem
  project_id           = platform-orchestrator_project.project.id
  env_type_id          = platform-orchestrator_environment_type.environment_type.id
}

# Enable GCP by uncommenting
# module "gcp" {
#   source = "./modules/gcp"
#   ...
# }
```

## Dependencies

### Module Dependencies
Each cloud module internally has these dependencies:
1. Cluster must be created first
2. Namespace is created (depends on cluster)
3. CloudNativePG is deployed (depends on cluster and namespace)
4. Runner is deployed (depends on cluster, namespace, CloudNativePG)
5. Environments are created (depends on runner) ← **NEW**
6. Humanitec resources reference the cluster and runner

Terraform handles this automatically through resource dependencies.

### External Dependencies
- **Humanitec Platform Orchestrator API** - For registering runners and resources
- **GitHub repositories** - Module sources (e.g., `git::https://github.com/humanitec-tutorials/first-deployment//modules/...`)
- **Helm charts** - Runner chart from `ghcr.io/humanitec/charts`
- **CloudNativePG Helm chart** - From `https://cloudnative-pg.github.io/charts`

## Environment Naming

Each cloud module creates two environments:
- `{cloud}-dev` - Development environment
- `{cloud}-score` - Environment for Score/Ansible VM-based workloads

Examples:
- AWS: `aws-dev`, `aws-score`
- GCP: `gcp-dev`, `gcp-score`
- Azure: `azure-dev`, `azure-score`

The `score` environment has a module rule that activates the `ansible-score-workload` module for VM-based deployments.

## Adding a New Cloud Provider

To add a new cloud provider (e.g., DigitalOcean):

1. **Create module directory**: `modules/digitalocean/`

2. **Add core infrastructure** (`main.tf`):
   - Kubernetes cluster
   - Networking (VPC, subnets)
   - IAM/service accounts

3. **Add provider configuration** (`providers.tf`):
   ```hcl
   data "digitalocean_kubernetes_cluster" "cluster" {
     name = digitalocean_kubernetes_cluster.cluster.name
   }
   
   provider "kubernetes" {
     host  = data.digitalocean_kubernetes_cluster.cluster.endpoint
     token = data.digitalocean_kubernetes_cluster.cluster.kube_config[0].token
     cluster_ca_certificate = base64decode(
       data.digitalocean_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate
     )
   }
   
   provider "helm" {
     kubernetes { ... }
   }
   ```

4. **Add namespace** (`namespace.tf`):
   ```hcl
   resource "kubernetes_namespace" "runner" {
     metadata {
       name = "${var.prefix}-humanitec-runner"
     }
   }
   ```

5. **Add CloudNativePG** (`cnpg.tf`):
   Deploy the operator to the cluster

6. **Add runner integration** (`runner.tf`):
   ```hcl
   module "runner" {
     source = "../shared/runner-integration"
     
     # Pass all required variables
   }
   ```

7. **Add environments** (`environments.tf`):
   ```hcl
   resource "platform-orchestrator_environment" "dev" {
     id          = "digitalocean-dev"
     project_id  = var.project_id
     env_type_id = var.env_type_id
     
     depends_on = [module.runner]
   }
   
   resource "platform-orchestrator_environment" "score" {
     id          = "digitalocean-score"
     project_id  = var.project_id
     env_type_id = var.env_type_id
     
     depends_on = [module.runner]
   }
   
   resource "platform-orchestrator_module_rule" "ansible_score_workload" {
     module_id  = "ansible-score-workload"
     env_id     = platform-orchestrator_environment.score.id
     project_id = var.project_id
   }
   ```

8. **Add Humanitec resources** (`humanitec-resources.tf`):
   Define any cloud-specific resource types and modules

9. **Add variables and outputs** (`variables.tf`, `outputs.tf`):
   Remember to include `project_id` and `env_type_id` variables!

10. **Add version requirements** (`versions.tf`)

11. **Update root main.tf**:
    ```hcl
    # module "digitalocean" {
    #   source = "./modules/digitalocean"
    #   project_id  = platform-orchestrator_project.project.id
    #   env_type_id = platform-orchestrator_environment_type.environment_type.id
    #   ...
    # }
    ```

## Modifying Shared Runner Logic

To change how the Humanitec runner is deployed across all clouds:

Edit [shared/runner-integration/main.tf](shared/runner-integration/main.tf). Changes will automatically apply to all cloud providers that call this module.

## Testing Modules

To test a specific cloud module:

1. Uncomment only the module you want to test in root `main.tf`
2. Run `terraform plan` and verify the plan
3. Run `terraform apply` to create infrastructure
4. Deploy to the cloud-specific environments (e.g., `aws-dev`, `aws-score`)
5. Run `./destroy-order.sh` to clean up

## Module Troubleshooting

### "no matching runner found" errors
**Cause**: Environment created before runner finished registration (should not happen with new architecture)
**Fix**: The `depends_on = [module.runner]` in `environments.tf` ensures runners exist first

### "Reference to undeclared module" errors
**Cause**: Trying to use a module that's commented out
**Fix**: Ensure the module is uncommented in root `main.tf`

### "Provider configuration not present" errors
**Cause**: Each module needs its own providers.tf
**Fix**: Verify `providers.tf` exists in the module and properly configures kubernetes/helm

### CloudNativePG namespace timeout during destroy
**Cause**: CRDs have finalizers that prevent deletion
**Fix**: The destroy script automatically handles this by waiting and retrying
