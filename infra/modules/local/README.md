# Local KinD Module

This module provides a local Kubernetes development environment using [KinD (Kubernetes in Docker)](https://kind.sigs.k8s.io/). It's perfect for local development, testing, and learning without incurring cloud costs.

## Features

- **Zero Cloud Costs** - Runs entirely on your local machine
- **Fast Iteration** - Instant feedback without cloud API delays
- **Easy DNS** - Uses localtest.me (automatically resolves to 127.0.0.1)
- **Ingress Ready** - NGINX Ingress Controller pre-configured
- **CloudNativePG** - In-cluster PostgreSQL support
- **Humanitec Integration** - Full Platform Orchestrator support

## Prerequisites

Before using this module, ensure you have:

1. **Docker Desktop** (or Docker Engine)
   ```bash
   docker --version
   ```

2. **KinD CLI**
   ```bash
   # macOS
   brew install kind

   # Linux
   curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
   chmod +x ./kind
   sudo mv ./kind /usr/local/bin/kind

   # Windows (PowerShell)
   curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
   Move-Item .\kind-windows-amd64.exe c:\some-dir-in-your-PATH\kind.exe
   ```

3. **kubectl**
   ```bash
   kubectl version --client
   ```

4. **Available Ports** - Ensure ports 80 and 443 are available (or configure custom ports)

## Quick Start

### 1. Enable the Local Module

The local module is enabled by default in [main.tf](../../main.tf):

```hcl
module "local" {
  source = "./modules/local"

  prefix               = local.prefix
  cluster_name         = var.local_cluster_name
  base_domain          = var.local_base_domain
  ingress_http_port    = var.local_ingress_http_port
  ingress_https_port   = var.local_ingress_https_port
  humanitec_org        = var.humanitec_org
  humanitec_auth_token = var.humanitec_auth_token
  public_key_pem       = tls_private_key.agent_runner_key.public_key_pem
  private_key_pem      = tls_private_key.agent_runner_key.private_key_pem
  project_id           = platform-orchestrator_project.project.id
  env_type_id          = platform-orchestrator_environment_type.environment_type.id
}
```

To disable it, comment out the entire module block.

### 2. Configure Variables

Create or edit `terraform.tfvars`:

```hcl
# Required
humanitec_org        = "your-org-id"
humanitec_auth_token = "your-token"

# Optional - customize if needed
prefix                  = "dev"                        # Default: random 4 chars
local_cluster_name      = "first-deployment-local"     # Default
local_base_domain       = "localtest.me"               # Default
local_ingress_http_port = 80                           # Default
local_ingress_https_port = 443                         # Default
```

### 3. Deploy

```bash
cd first-deployment/infra
terraform init
terraform plan
terraform apply
```

This will:
1. Create a KinD cluster
2. Install NGINX Ingress Controller
3. Install CloudNativePG operator
4. Deploy Humanitec runner
5. Create `{prefix}-local-dev` environment

### 4. Deploy Your Application

```bash
# Deploy using hctl
hctl deploy {prefix}-tutorial {prefix}-local-dev ./score.yaml

# Or deploy a manifest
hctl deploy {prefix}-tutorial {prefix}-local-dev ./manifest.yaml
```

### 5. Access Your Application

Applications are accessible at:
- **HTTP**: `http://{app-name}.localtest.me`
- **HTTPS**: `https://{app-name}.localtest.me` (if TLS configured)

**Example**: If you deploy an app called `api`, access it at:
```bash
curl http://api.localtest.me
```

## Domain Configuration

### Using localtest.me (Default)

**localtest.me** is a special domain that automatically resolves to `127.0.0.1`:
- `localtest.me` → `127.0.0.1`
- `*.localtest.me` → `127.0.0.1`
- `app.localtest.me` → `127.0.0.1`
- `api.service.localtest.me` → `127.0.0.1`

**Benefits**:
- No `/etc/hosts` editing required
- Works immediately
- Supports unlimited subdomains
- No DNS configuration needed

### Using a Custom Domain

If you prefer a custom domain:

1. **Configure in terraform.tfvars**:
   ```hcl
   local_base_domain = "myapp.local"
   ```

2. **Add to /etc/hosts**:
   ```bash
   echo "127.0.0.1 myapp.local *.myapp.local" | sudo tee -a /etc/hosts
   ```

3. **Apply configuration**:
   ```bash
   terraform apply
   ```

## Port Configuration

### Default Ports

By default, the module binds to:
- **HTTP**: Port 80
- **HTTPS**: Port 443

### Custom Ports

If ports 80/443 are in use, configure custom ports:

```hcl
# terraform.tfvars
local_ingress_http_port  = 8080
local_ingress_https_port = 8443
```

Then access applications at:
```bash
curl http://app.localtest.me:8080
```

## Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enabled` | Whether to create the local cluster | `true` | No |
| `prefix` | Prefix for resource names | (from root) | Yes |
| `cluster_name` | KinD cluster name suffix | `first-deployment-local` | No |
| `base_domain` | Base domain for ingress | `localtest.me` | No |
| `ingress_http_port` | HTTP port on host | `80` | No |
| `ingress_https_port` | HTTPS port on host | `443` | No |
| `humanitec_org` | Humanitec organization ID | (from root) | Yes |
| `humanitec_auth_token` | Humanitec API token | (from root) | Yes |
| `public_key_pem` | Runner public key | (from root) | Yes |
| `private_key_pem` | Runner private key | (from root) | Yes |
| `project_id` | Humanitec project ID | (from root) | Yes |
| `env_type_id` | Environment type ID | (from root) | Yes |

## Outputs

| Output | Description |
|--------|-------------|
| `cluster_name` | Full name of the KinD cluster |
| `kubeconfig_context` | Kubeconfig context name |
| `base_domain` | Base domain for applications |
| `ingress_http_url` | HTTP access URL |
| `ingress_https_url` | HTTPS access URL |
| `runner_namespace` | Runner namespace |
| `environment_id` | Environment ID |

## Troubleshooting

### Cluster Creation Fails

**Issue**: KinD cluster creation fails

**Solution**:
```bash
# Check if Docker is running
docker ps

# Check if cluster already exists
kind get clusters

# Delete existing cluster if needed
kind delete cluster --name {prefix}-first-deployment-local
```

### Port Already in Use

**Issue**: Ports 80 or 443 are already bound

**Solutions**:

1. **Stop conflicting services**:
   ```bash
   # macOS - Stop Apache
   sudo apachectl stop

   # Linux - Stop nginx
   sudo systemctl stop nginx
   ```

2. **Use custom ports**:
   ```hcl
   # terraform.tfvars
   local_ingress_http_port  = 8080
   local_ingress_https_port = 8443
   ```

### Cannot Access Applications

**Issue**: Applications don't respond at `*.localtest.me`

**Checks**:

1. **Verify ingress is ready**:
   ```bash
   kubectl --context kind-{prefix}-first-deployment-local \
     -n ingress-nginx get pods
   ```

2. **Check ingress rules**:
   ```bash
   kubectl --context kind-{prefix}-first-deployment-local \
     get ingress -A
   ```

3. **Test direct access**:
   ```bash
   curl -v http://localhost
   ```

4. **Verify DNS resolution**:
   ```bash
   nslookup app.localtest.me
   # Should return: 127.0.0.1
   ```

### Runner Not Connecting

**Issue**: Humanitec runner fails to connect

**Checks**:

1. **Check runner logs**:
   ```bash
   kubectl --context kind-{prefix}-first-deployment-local \
     -n {prefix}-humanitec-runner logs -l app.kubernetes.io/name=humanitec-kubernetes-agent-runner
   ```

2. **Verify runner registration**:
   ```bash
   hctl get runners
   ```

3. **Check authentication**:
   ```bash
   # Verify keys are configured
   terraform output -json | jq '.runner'
   ```

## Cleanup

### Destroy Everything

```bash
terraform destroy
```

This will:
1. Delete the Humanitec environment
2. Remove the runner
3. Delete the KinD cluster
4. Clean up all resources

### Manual Cleanup

If Terraform fails:

```bash
# Delete the cluster manually
kind delete cluster --name {prefix}-first-deployment-local

# Clean up Terraform state
terraform state rm module.local
```

## Multi-Environment Setup

You can run the local module alongside cloud modules:

```hcl
# Enable multiple environments
module "local" { ... }  # local-dev
module "gcp" { ... }    # gcp-dev, gcp-score
module "aws" { ... }    # aws-dev, aws-score
```

Then choose deployment target by environment:
```bash
# Deploy locally
hctl deploy myapp local-dev ./score.yaml

# Deploy to GCP
hctl deploy myapp gcp-dev ./score.yaml

# Deploy to AWS
hctl deploy myapp aws-dev ./score.yaml
```

## Performance Tips

1. **Resource Limits**: KinD clusters use Docker resources
   - Allocate sufficient CPU/memory in Docker Desktop
   - Recommended: 4 CPUs, 8GB RAM minimum

2. **Image Loading**: Load images directly into KinD for faster iteration
   ```bash
   kind load docker-image my-image:latest --name {prefix}-first-deployment-local
   ```

3. **Persistent Storage**: KinD uses local storage by default
   - Data persists within the cluster lifecycle
   - Destroyed when cluster is deleted

## Advanced Configuration

### Custom KinD Configuration

To customize the KinD cluster configuration, modify [main.tf](main.tf):

```hcl
# Add extra port mappings
extraPortMappings:
- containerPort: 3000
  hostPort: 3000
  protocol: TCP

# Add worker nodes
nodes:
- role: control-plane
  ...
- role: worker
- role: worker
```

### TLS/HTTPS Setup

To enable HTTPS with self-signed certificates:

1. Generate certificates
2. Create Kubernetes secret
3. Configure Ingress with TLS

See the Humanitec documentation for details.

## Resources

- [KinD Documentation](https://kind.sigs.k8s.io/)
- [localtest.me Info](http://readme.localtest.me/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [CloudNativePG](https://cloudnative-pg.io/)
- [Humanitec Platform Orchestrator](https://developer.humanitec.com/)
