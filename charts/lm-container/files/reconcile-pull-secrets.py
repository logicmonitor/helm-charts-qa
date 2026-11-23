"""Maintain configured references without replacing platform-managed references."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


OWNED = "logicmonitor.com/managed-pull-secrets"
PLATFORM = "openshift.io/internal-registry-pull-secret-ref"
MANAGER = "lm-container-pull-secrets"
PAUSE = "logicmonitor.com/pull-secrets-pause-until"
ACK = "logicmonitor.com/pull-secrets-paused"


class Kubernetes:
    def __init__(self):
        directory = Path("/var/run/secrets/kubernetes.io/serviceaccount")
        host = os.environ["KUBERNETES_SERVICE_HOST"]
        if ":" in host:
            host = "[" + host.strip("[]") + "]"
        self.server = "https://{}:{}".format(
            host, os.environ.get("KUBERNETES_SERVICE_PORT_HTTPS", "443")
        )
        self.token_path = directory / "token"
        self.context = ssl.create_default_context(cafile=str(directory / "ca.crt"))

    def request(self, method, path, body=None, content_type="application/json"):
        request = urllib.request.Request(
            self.server + path,
            data=None if body is None else json.dumps(body).encode(),
            method=method,
            headers={
                "Authorization": "Bearer " + self.token_path.read_text().strip(),
                "Content-Type": content_type,
            },
        )
        try:
            with urllib.request.urlopen(request, context=self.context, timeout=20) as result:
                return json.load(result)
        except urllib.error.HTTPError as error:
            error.close()
            raise


def references(values):
    result = []
    for value in values:
        name = value if isinstance(value, str) else value["name"]
        if not isinstance(name, str) or not name:
            raise ValueError("Pull secret references must have a non-empty name")
        if name not in result:
            result.append(name)
    return result


def plan(account, desired):
    annotations = account["metadata"].get("annotations", {})
    previous = json.loads(annotations.get(OWNED, "[]"))
    if not isinstance(previous, list) or any(not isinstance(n, str) for n in previous):
        raise ValueError("Invalid managed-pull-secrets annotation")
    current = references(account.get("imagePullSecrets", []))
    protected = annotations.get(PLATFORM)
    keep = [name for name in current if name not in previous or name == protected]
    if protected and protected not in keep:
        keep.append(protected)
    combined = list(dict.fromkeys(keep + desired))
    owned = [name for name in desired if name != protected]
    return [{"name": name} for name in combined], owned


def reconcile(api, target, release, release_namespace, create=False):
    namespace, name = target["namespace"], target["name"]
    path = "/api/v1/namespaces/{}/serviceaccounts/{}".format(
        urllib.parse.quote(namespace, safe=""), urllib.parse.quote(name, safe="")
    )
    for attempt in range(8):
        try:
            try:
                account = api.request("GET", path)
            except urllib.error.HTTPError as error:
                error.close()
                if error.code == 404:
                    if not create:
                        return False
                    desired = references(target["secrets"])
                    api.request("POST", path.rsplit("/", 1)[0], {
                        "apiVersion": "v1", "kind": "ServiceAccount",
                        "metadata": {
                            "name": name, "namespace": namespace,
                            "labels": {"app.kubernetes.io/managed-by": "Helm"},
                            "annotations": {
                                "meta.helm.sh/release-name": release,
                                "meta.helm.sh/release-namespace": release_namespace,
                                OWNED: json.dumps(desired, separators=(",", ":")),
                                "logicmonitor.com/pull-secrets-apply-mode": "server",
                            },
                        },
                        "imagePullSecrets": [{"name": value} for value in desired],
                    })
                    account = api.request("GET", path)
                else:
                    raise
            metadata = account["metadata"]
            annotations = metadata.get("annotations", {})
            if (
                annotations.get("meta.helm.sh/release-name") != release
                or annotations.get("meta.helm.sh/release-namespace") != release_namespace
            ):
                raise ValueError("Refusing to modify an account not owned by this release: " + name)

            # Applying the identical list shares ownership without forcing a
            # conflict. This keeps the list present when Helm later omits it,
            # including clusters where the internal registry is disabled.
            shared_annotations = {}
            if OWNED in annotations:
                shared_annotations[OWNED] = annotations[OWNED]
            shared = api.request(
                "PATCH", path + "?fieldManager=" + MANAGER,
                {
                    "apiVersion": "v1", "kind": "ServiceAccount",
                    "metadata": {
                        "name": name, "namespace": namespace,
                        "resourceVersion": metadata["resourceVersion"],
                        "annotations": shared_annotations,
                    },
                    "imagePullSecrets": account.get("imagePullSecrets", []),
                },
                "application/apply-patch+yaml",
            )
            desired, owned = plan(shared, references(target["secrets"]))
            old_annotations = shared["metadata"].get("annotations", {})
            encoded = json.dumps(owned, separators=(",", ":"))
            if desired == shared.get("imagePullSecrets", []) and old_annotations.get(OWNED) == encoded:
                return True
            operations = [
                {"op": "test", "path": "/metadata/resourceVersion", "value": shared["metadata"]["resourceVersion"]},
                {"op": "add", "path": "/imagePullSecrets", "value": desired},
            ]
            if "annotations" not in shared["metadata"]:
                operations.append({"op": "add", "path": "/metadata/annotations", "value": {}})
            operations.append({
                "op": "add", "path": "/metadata/annotations/" + OWNED.replace("/", "~1"),
                "value": encoded,
            })
            api.request("PATCH", path + "?fieldManager=" + MANAGER, operations, "application/json-patch+json")
            print("Reconciled {}/{}".format(namespace, name), flush=True)
            return True
        except urllib.error.HTTPError as error:
            error.close()
            if error.code not in (409, 422) or attempt == 7:
                raise
            time.sleep(min(0.1 * (attempt + 1), 1))
    return False


def fingerprint(config):
    return hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest()


def config_path(config):
    return "/api/v1/namespaces/{}/configmaps/{}".format(config["releaseNamespace"], config["configName"])


def annotate(api, path, obj, key, value):
    operations = [{"op": "test", "path": "/metadata/resourceVersion", "value": obj["metadata"]["resourceVersion"]}]
    if "annotations" not in obj["metadata"]:
        operations.append({"op": "add", "path": "/metadata/annotations", "value": {}})
    operations.append({"op": "add", "path": "/metadata/annotations/" + key.replace("/", "~1"), "value": value})
    api.request("PATCH", path, operations, "application/json-patch+json")


def pause_current(api, config):
    path = config_path(config)
    expected = fingerprint(config)
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        try:
            current = api.request("GET", path)
        except urllib.error.HTTPError as error:
            error.close()
            if error.code == 404:
                return
            raise
        if fingerprint(json.loads(current["data"]["targets.json"])) == expected:
            return
        annotations = current["metadata"].get("annotations", {})
        if annotations.get(PAUSE) != expected:
            try:
                annotate(api, path, current, PAUSE, expected)
            except urllib.error.HTTPError as error:
                if error.code not in (409, 422):
                    raise
        elif annotations.get(ACK) == expected:
            return
        time.sleep(1)
    raise RuntimeError("Timed out waiting for the running pull-secret helper to pause; check its logs")


def load_current(api, initial):
    path = config_path(initial)
    current = api.request("GET", path)
    config = json.loads(current["data"]["targets.json"])
    annotations = current["metadata"].get("annotations", {})
    pending = annotations.get(PAUSE)
    if pending and pending != fingerprint(config):
        if annotations.get(ACK) != pending:
            annotate(api, path, current, ACK, pending)
        return None
    return config


def cleanup(api, config):
    name = config["bootstrapName"]
    paths = []
    for namespace in config["namespaces"]:
        for resource in ("roles", "rolebindings"):
            paths.append("/apis/rbac.authorization.k8s.io/v1/namespaces/{}/{}/{}".format(namespace, resource, name))
    for resource in ("configmaps", "serviceaccounts"):
        paths.append("/api/v1/namespaces/{}/{}/{}".format(config["releaseNamespace"], resource, name))
    for path in paths:
        try:
            api.request("DELETE", path)
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="/config/targets.json")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--cleanup", action="store_true")
    arguments = parser.parse_args()
    api = Kubernetes()
    initial = json.loads(Path(arguments.config).read_text())
    if arguments.cleanup:
        cleanup(api, initial)
        return
    if arguments.once:
        pause_current(api, initial)
    while True:
        try:
            config = initial if arguments.once else load_current(api, initial)
        except Exception as error:
            print("Failed to reload pull-secret configuration: " + str(error), flush=True)
            if arguments.once:
                raise
            time.sleep(initial["intervalSeconds"])
            continue
        if config is None:
            time.sleep(1)
            continue
        ready = True
        for target in config["targets"]:
            try:
                reconciled = reconcile(api, target, config["release"], config["releaseNamespace"],
                                       create=arguments.once and config["createAccounts"])
                if arguments.once and not reconciled and target["secrets"] and config["createAccounts"]:
                    raise RuntimeError("Could not bootstrap " + target["name"])
                ready = reconciled and ready
            except Exception as error:
                ready = False
                print("Reconciliation failed for {}: {}".format(target["name"], error), flush=True)
                if arguments.once:
                    raise
        if arguments.once:
            return
        marker = Path("/state/ready")
        if ready:
            marker.touch()
        else:
            marker.unlink(missing_ok=True)
        time.sleep(config["intervalSeconds"])


if __name__ == "__main__":
    main()
