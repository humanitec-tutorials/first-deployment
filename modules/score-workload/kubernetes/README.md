# score-workload-tofu

This is a Terraform / OpenTofu compatible module to be used to provision `score-workload` resources ontop of Kubernetes for the Humanitec Orchestrator.

## Requirements

1. There must be a module provider setup for `kubernetes` (`hashicorp/kubernetes`).
2. There must be a resource type setup for `score-workload`, for example:

    ```
    canyon create resource-type score-workload --set=name='Score Workload' --set=output_schema='{"type":"object","properties":{}}'
    ```

## Installation

Install this with the `canyon` CLI, you should replace the `CHANGEME` in the provider mapping with your real provider type and alias for Kubernetes; and replace the CHANGEME in module_inputs with the real target namespace.

```shell
canyon create module-definition \
    --set=resource_type=score-workload \
    --set=module_source=git::https://github.com/humanitec/module-definition-library//score-workload/kubernetes \
    --set=provider_mapping='{"kubernetes": "CHANGEME"}' \
    --set=module_inputs='{"namespace": "CHANGEME"}'
```

## Resource Outputs

The following outputs are exposed

| Name            | Description                                             | Type     |
| --------------- | ------------------------------------------------------- | -------- |
| `loadbalancer`  | The dns name of the clusterip service for this workload | `string` |

## Module Inputs

The following input variables can be set in the `module_inputs` of the `canyon create module-definition` command.

| Name                     | Description                                           | Type       | Default | Required |
| ------------------------ | ----------------------------------------------------- | ---------- | ------- | -------- |
| `namespace`              | The namespace to deploy to.                           | `string`   |         | yes      |
| `service_account_name`   | The name of the service account to use for the pods.  | `string`   | `null`  | no       |
| `additional_annotations` | Additional annotations to add to all resources.       | `map(string)` | `{}`    | no       |
| `wait_for_rollout`       | Whether to wait for the workload to be rolled out.    | `bool`     | `true`  | no       |

For example, to set the `service_account_name` and disable `wait_for_rollout`, you would use:

```shell
canyon create module-definition \
    ...
    --set=module_inputs='{"namespace": "my-namespace", "service_account_name": "my-sa", "wait_for_rollout": false}'
```

### Dynamic namespaces

Instead of a hardcoded destination namespace, you can use the resource graph to provision a namespace.

1. Ensure there is a resource type for the namespace (eg: `k8s-namespace`) and that there is a definition and rule set up for it in the target environments.
2. Add a dependency to the create module definition request:

    ```
    --set=dependencies='{"ns": {"type": "k8s-namespace"}}'
    ```

3. In the module inputs replace this with the placeholder:

    ```
    --set=module_inputs='{"namespace": "${ resources.ns.outputs.name }"}'
    ```
