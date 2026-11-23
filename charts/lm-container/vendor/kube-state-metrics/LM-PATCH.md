This is the upstream prometheus-community/kube-state-metrics chart 7.2.2,
vendored from the pinned dependency package. The upstream chart is Apache-2.0.

The only upstream template change is templates/serviceaccount.yaml. When the
lm-container OpenShift pull-secret helper is enabled, this template omits
references from server-side releases. The pre-install helper creates the
accounts before Helm applies the remaining metadata. The shared lmutil
templates implement that decision. Helm 3 and
detected legacy client-side releases retain their existing rendering behavior.

Keep this patch when updating the upstream dependency. This copy is intended
for use as an lm-container dependency, where lmutil is available.
