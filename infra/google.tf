provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

resource "google_compute_network" "vpc" {
  count = local.create_gcp ? 1 : 0

  name                    = "${local.prefix}-first-deployment-vpc"
  auto_create_subnetworks = "false"
}

resource "google_compute_subnetwork" "subnet" {
  count = local.create_gcp ? 1 : 0

  name          = "${local.prefix}-first-deployment-subnet"
  region        = var.gcp_region
  network       = google_compute_network.vpc[0].name
  ip_cidr_range = "10.10.0.0/24"
}

resource "google_container_cluster" "cluster" {
  count = local.create_gcp ? 1 : 0

  name     = "${local.prefix}-first-deployment-gke"
  location = var.gcp_region

  initial_node_count = 2

  network    = google_compute_network.vpc[0].name
  subnetwork = google_compute_subnetwork.subnet[0].name

  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }
}


resource "google_iam_workload_identity_pool" "wip" {
  count = local.create_gcp ? 1 : 0

  workload_identity_pool_id = "${local.prefix}-first-deployment-wip"
}

resource "google_iam_workload_identity_pool_provider" "wip_provider" {
  count = local.create_gcp ? 1 : 0

  workload_identity_pool_id          = google_iam_workload_identity_pool.wip[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "${local.prefix}-first-deploy-wip-provider"
  attribute_mapping = {
    "google.subject" = "assertion.sub"
  }
  oidc {
    issuer_uri = "https://oidc.humanitec.dev"
  }
}

resource "google_service_account" "runner" {
  count = local.create_gcp ? 1 : 0

  account_id   = "${local.prefix}-first-deployment-runner"
  display_name = "Used by Humanitec Orchestrator to access GKE clusters for launching runners"
}

data "google_project" "project" {
  project_id = var.gcp_project_id
}

resource "google_service_account_iam_member" "runner_workload_identity_binding" {
  count = local.create_gcp ? 1 : 0

  service_account_id = google_service_account.runner[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.wip[0].workload_identity_pool_id}/subject/${var.humanitec_org}+${local.prefix}-first-deployment-gke-runner"
}

resource "google_project_iam_custom_role" "runner" {
  count = local.create_gcp ? 1 : 0

  role_id     = "${local.prefix}_first_deployment_runner_role"
  title       = "${local.prefix}_first_deployment_runner_role"
  description = "Access for the Humanitec Orchestrator to GKE clusters for launching runners"
  project     = var.gcp_project_id

  permissions = [
    # Container/GKE permissions
    "container.clusters.get",
    "container.clusters.list",
    "container.clusters.create",
    "container.clusters.update",
    "container.clusters.delete",
    "container.nodes.list",
    "container.nodes.get",
    "container.operations.get",
    "container.operations.list",
    
    # Storage permissions
    "storage.buckets.create",
    "storage.buckets.delete",
    "storage.buckets.get",
    "storage.buckets.list",
    "storage.buckets.update",
    "storage.objects.create",
    "storage.objects.delete",
    "storage.objects.get",
    "storage.objects.list",
    "storage.objects.update",
    "storage.objects.create",
    "storage.objects.get",
    "storage.objects.list",
    "storage.objects.update",
    
    # Pub/Sub permissions
    "pubsub.topics.create",
    "pubsub.topics.delete",
    "pubsub.topics.get",
    "pubsub.topics.list",
    "pubsub.topics.update",
    "pubsub.subscriptions.create",
    "pubsub.subscriptions.delete",
    "pubsub.subscriptions.get",
    "pubsub.subscriptions.list",
    "pubsub.subscriptions.update",
    "pubsub.snapshots.create",
    "pubsub.snapshots.delete",
    "pubsub.snapshots.get",
    "pubsub.snapshots.list",
    "pubsub.snapshots.update",
    
    # IAM permissions
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.setIamPolicy",
    "iam.serviceAccounts.create",
    "iam.serviceAccounts.delete",
    "iam.serviceAccounts.update",
    "iam.serviceAccounts.list",
    "iam.roles.get",
    "iam.roles.list",
    "iam.roles.create",
    "iam.roles.delete",
    "iam.roles.update",
    "iam.roles.undelete",
    "iam.serviceAccountKeys.create",
    "iam.serviceAccountKeys.delete",
    "iam.serviceAccountKeys.get",
    "iam.serviceAccountKeys.list",
    "iam.workloadIdentityPools.get",
    "iam.workloadIdentityPools.list",
    "iam.workloadIdentityPools.create",
    "iam.workloadIdentityPools.delete",
    "iam.workloadIdentityPools.update",
    "iam.workloadIdentityPoolProviders.get",
    "iam.workloadIdentityPoolProviders.list",
    "iam.workloadIdentityPoolProviders.create",
    "iam.workloadIdentityPoolProviders.delete",
    "iam.workloadIdentityPoolProviders.update",
    
    # Compute permissions
    "compute.instances.get",
    "compute.instances.list",
    "compute.instances.create",
    "compute.instances.update",
    "compute.instances.delete",
    "compute.networks.get",
    "compute.networks.list",
    "compute.subnetworks.get",
    "compute.subnetworks.list",
    "cloudnotifications.activities.list",
    "compute.addresses.use",
    "compute.addresses.useInternal",
    "compute.disks.create",
    "compute.disks.createTagBinding",
    "compute.disks.delete",
    "compute.disks.get",
    "compute.disks.setLabels",
    "compute.disks.use",
    "compute.disks.useReadOnly",
    "compute.forwardingRules.create",
    "compute.forwardingRules.delete",
    "compute.globalOperations.get",
    "compute.healthChecks.create",
    "compute.healthChecks.delete",
    "compute.healthChecks.get",
    "compute.healthChecks.update",
    "compute.images.useReadOnly",
    "compute.instanceGroupManagers.get",
    "compute.instanceTemplates.useReadOnly",
    "compute.instances.attachDisk",
    "compute.instances.create",
    "compute.instances.createTagBinding",
    "compute.instances.delete",
    "compute.instances.detachDisk",
    "compute.instances.get",
    "compute.instances.setDeletionProtection",
    "compute.instances.setLabels",
    "compute.instances.setMetadata",
    "compute.instances.setServiceAccount",
    "compute.instances.setTags",
    "compute.instances.start",
    "compute.instances.stop",
    "compute.instances.update",
    "compute.instances.updateDisplayDevice",
    "compute.instances.use",
    "compute.machineImages.useReadOnly",
    "compute.networkEndpointGroups.attachNetworkEndpoints",
    "compute.networkEndpointGroups.create",
    "compute.networkEndpointGroups.delete",
    "compute.networkEndpointGroups.use",
    "compute.networks.use",
    "compute.networks.useExternalIp",
    "compute.regionBackendServices.create",
    "compute.regionBackendServices.delete",
    "compute.regionBackendServices.get",
    "compute.regionBackendServices.update",
    "compute.regionBackendServices.use",
    "compute.regionOperations.get",
    "compute.resourcePolicies.use",
    "compute.snapshots.useReadOnly",
    "compute.subnetworks.use",
    "compute.subnetworks.useExternalIp",
    "compute.zoneOperations.get",
    "compute.zones.get",
    "compute.instanceGroups.create",
    "compute.instanceGroups.update",
    "compute.instanceGroups.delete",
    "compute.instanceGroups.use",
    "compute.instanceGroups.get",
    "compute.firewalls.create",
    "compute.firewalls.get",
    "compute.firewalls.list",
    "compute.firewalls.update",
    "compute.firewalls.delete",
    "compute.networks.updatePolicy",
    "compute.httpHealthChecks.create",
    "compute.httpHealthChecks.get",
    "compute.httpHealthChecks.list",
    "compute.httpHealthChecks.update",
    "compute.httpHealthChecks.delete",
    "compute.backendServices.create",
    "compute.backendServices.get",
    "compute.backendServices.list",
    "compute.backendServices.update",
    "compute.backendServices.delete",
    "compute.httpHealthChecks.useReadOnly",
    "compute.backendServices.use",
    "compute.urlMaps.create",
    "compute.urlMaps.get",
    "compute.urlMaps.list",
    "compute.urlMaps.update",
    "compute.urlMaps.delete",
    "compute.urlMaps.use",
    "compute.targetHttpProxies.create",
    "compute.targetHttpProxies.get",
    "compute.targetHttpProxies.list",
    "compute.targetHttpProxies.update",
    "compute.targetHttpProxies.delete",
    "compute.targetHttpProxies.use",
    "compute.globalForwardingRules.create",
    "compute.globalForwardingRules.get",
    "compute.globalForwardingRules.list",
    "compute.globalForwardingRules.update",
    "compute.globalForwardingRules.delete"
  ]
}

resource "google_project_iam_member" "runner_role_binding" {
  count = local.create_gcp ? 1 : 0

  project = var.gcp_project_id
  role    = "projects/${var.gcp_project_id}/roles/${google_project_iam_custom_role.runner[0].role_id}"
  member  = "serviceAccount:${google_service_account.runner[0].email}"
}
