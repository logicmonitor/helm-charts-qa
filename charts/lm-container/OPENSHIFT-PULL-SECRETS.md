# OpenShift pull-secret testing

This implementation keeps custom pull-secret references on ServiceAccounts.
Pods continue to inherit their ServiceAccount's combined references. It covers
Argus, collectorset-controller, collector, and the bundled kube-state-metrics.

It does not modify CSC application code, application security contexts, SCCs,
or existing application RBAC. It adds a separate helper and namespace-scoped
RBAC for that helper. Registry Secret contents are not read by the helper.

## Build the local chart

From the repository root:

```bash
python3 scripts/package-lm-container-test.py
```

The test package is written to:

```text
/private/tmp/lm-container-helm4-test/lm-container-13.4.0-rc01.tgz
```

The filename follows the current Chart.yaml version. The packaging script
builds lmutil, Argus, CSC, and the patched KSM dependency from local sources in
a temporary directory, then refreshes the local charts' dependency caches.
Run it again after editing those sources, even when installing from the chart
directory, so Helm does not load older cached templates. Other dependencies must already be present in
charts/lm-container/charts. It does not install anything or change the Helm
apply mode. Do not test the published QA package: it does not include these
unpublished changes.

## Upgrade the existing Helm 4 test release

Keep the same custom secret references for this first migration. The example
uses release helm-v4-01 and namespace moulika-oc.

Confirm the target cluster and secret:

```bash
oc config current-context
oc get secret lm-private-registry -n moulika-oc
helm version --short
```

Save the release's user-supplied values. This file can contain LM credentials,
so it is created with restricted permissions. Use `helm get values` without
`--all`; the new chart needs its new defaults.

```bash
(
  umask 077
  helm get values helm-v4-01 -n moulika-oc -o yaml \
    > /private/tmp/lm-container-helm4-test/existing-values.yaml
)
```

Upgrade using the new package:

```bash
helm upgrade helm-v4-01 \
  /private/tmp/lm-container-helm4-test/lm-container-13.4.0-rc01.tgz \
  --namespace moulika-oc \
  --reset-values \
  --values /private/tmp/lm-container-helm4-test/existing-values.yaml \
  --set-string 'global.imagePullSecrets[0].name=lm-private-registry' \
  --wait --timeout 10m
```

Run the identical upgrade again after OpenShift has updated the accounts.
Both upgrades must succeed. No `--server-side=false` or force-conflicts flag
is used.

`--reset-values` loads the new defaults and reapplies the exported user values.
Plain `--reuse-values` can retain the old chart defaults and omit the new helper
settings. The chart rejects that situation with an explanatory message.

Inspect references and helper logs:

```bash
oc get serviceaccounts -n moulika-oc \
  -o 'custom-columns=NAME:.metadata.name,PULL-SECRETS:.imagePullSecrets[*].name'

oc logs deployment/helm-v4-01-pull-secrets -n moulika-oc --tail=50
```

Each application account should retain its OpenShift-managed references and
the configured custom references. The helper's own accounts do not need the
application's custom secret because its image must be independently pullable.

## Fresh installation

Use the normal `helm install` command with this local package, your complete
installation values, and the custom secret reference. The secret must already
exist in the installation namespace.

On native Helm 4 server-side releases, pre-install hooks create the application
ServiceAccounts and seed their references before application pods are created.
Helm then applies the account metadata without applying imagePullSecrets.
Helm 3 retains its normal account creation and client-side update behavior.

For a fresh release on the same cluster, account for the chart's existing
cluster-wide SCC names and ownership. A different release name or namespace
does not isolate those SCCs.

## What to test

1. Fresh Helm 4 install with empty references, then repeated upgrades.
2. Fresh Helm 4 install with custom references, wait for OpenShift's controller,
   then repeat the upgrade twice.
3. Upgrade the previous chart with the same custom references, then repeat.
4. Replace a custom reference; verify only the old configured reference is
   removed and platform/unknown references remain.
5. Remove all custom references; verify OpenShift references remain.
6. Recreate application pods and check their inherited references. Existing
   pods do not automatically receive later changes to a ServiceAccount list.
7. Repeat with Helm 3 and with a Helm 3-created release upgraded using Helm 4.
8. Exercise rollback between releases of this implementation and uninstall.
9. Use real private images to verify credentials. An empty dockerconfigjson
   and public images test reference handling, not authenticated pulls.

## Implementation and limits

- The helper checks live account ownership and refuses to modify another
  release's account. Externally supplied accounts (`serviceAccount.create:
  false`) are left to their owner.
- Before a native server-side upgrade, a Job reconciles the new desired list.
  It pauses the running helper when configuration changes, avoiding competing
  old and new configurations. The normal helper resumes when Helm updates its
  ConfigMap. An interrupted upgrade can leave it paused; retry the upgrade or
  roll back to another release of this implementation.
- Updates use resource-version checks and retries. The helper shares ownership
  of the unchanged live list through server-side apply, then patches changes
  without force-conflicts. This allows Helm to omit the list without deleting
  it even when OpenShift's internal registry is disabled.
- A ServiceAccount annotation records managed custom references. Other entries
  are preserved, including the platform reference identified by OpenShift's
  annotation. On the first migration there is no reliable history of removed
  custom references, so migrate with unchanged references before changing them.
  Unrecognized pre-migration entries are preserved rather than guessed at.
- Helm 3 and detected legacy client-side releases retain their client-side
  list rendering. Existing account annotations and managed fields are used to
  recognize that path; the chart does not switch the Helm release's apply mode.
- Bootstrap RBAC allows creating ServiceAccounts in the target namespace;
  Kubernetes cannot restrict `create` by resource name. Reads and patches are
  restricted to the named application accounts. The normal helper cannot
  create accounts. ConfigMap access and hook cleanup are also restricted to
  named resources. No Secret-read or cluster-wide helper permissions are added.
- The helper image defaults to public `docker.io/library/python:3.12-alpine`.
  Configure `openshiftPullSecrets.image` to an independently pullable mirror
  when Docker Hub is unavailable. It cannot depend on the secret it is bootstrapping.
- The KSM dependency is a vendored 7.2.2 chart with one template patch. Retain
  that patch when updating KSM. Standalone Argus/CSC installations do not enable
  this umbrella helper by default.
- Rollback to an older chart that still applies a custom-only list can
  reintroduce the original conflict. Offline `helm template` cannot inspect
  existing release apply-mode annotations; use connected Helm operations to
  test migration.
- This is a cluster-test candidate. Local Kubernetes tests simulate OpenShift
  list updates; actual ARO admission, SCC behavior, and private-image pulls
  still require validation on ARO before a production release.

## Local unit tests

```bash
python3 -m unittest discover -s tests -p test_openshift_pull_secrets.py -v
```
