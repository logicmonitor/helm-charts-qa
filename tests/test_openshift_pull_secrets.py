import copy
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError


SOURCE = Path(__file__).resolve().parents[1] / "charts/lm-container/files/reconcile-pull-secrets.py"
spec = importlib.util.spec_from_file_location("pull_secrets", SOURCE)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def account(names, owned=None, platform=None):
    annotations = {"meta.helm.sh/release-name": "test", "meta.helm.sh/release-namespace": "test"}
    if owned is not None:
        annotations[helper.OWNED] = json.dumps(owned)
    if platform:
        annotations[helper.PLATFORM] = platform
    return {"metadata": {"name": "test-argus", "namespace": "test", "resourceVersion": "1",
                         "annotations": annotations},
            "imagePullSecrets": [{"name": name} for name in names]}


class PlanTests(unittest.TestCase):
    def test_add_preserves_platform_and_unknown_entries(self):
        result, owned = helper.plan(account(["platform", "external"]), ["custom"])
        self.assertEqual(helper.references(result), ["platform", "external", "custom"])
        self.assertEqual(owned, ["custom"])

    def test_replace_removes_only_previous_managed_reference(self):
        result, owned = helper.plan(account(["platform", "old", "external"], ["old"]), ["new"])
        self.assertEqual(helper.references(result), ["platform", "external", "new"])
        self.assertEqual(owned, ["new"])

    def test_remove_all_keeps_platform(self):
        result, owned = helper.plan(account(["custom", "platform"], ["custom"]), [])
        self.assertEqual(helper.references(result), ["platform"])
        self.assertEqual(owned, [])

    def test_platform_reference_is_never_removed_even_if_previously_tracked(self):
        result, owned = helper.plan(account(["platform"], ["platform"], "platform"), [])
        self.assertEqual(helper.references(result), ["platform"])
        self.assertEqual(owned, [])

    def test_configured_platform_reference_is_not_tracked(self):
        result, owned = helper.plan(account(["platform"], platform="platform"), ["platform"])
        self.assertEqual(helper.references(result), ["platform"])
        self.assertEqual(owned, [])

    def test_missing_platform_reference_is_restored_from_platform_annotation(self):
        result, _ = helper.plan(account(["custom"], ["custom"], "platform"), ["custom"])
        self.assertEqual(helper.references(result), ["platform", "custom"])

    def test_migration_preserves_unrecognized_old_references(self):
        result, _ = helper.plan(account(["previous-chart-secret", "platform"]), ["new"])
        self.assertEqual(helper.references(result), ["previous-chart-secret", "platform", "new"])

    def test_duplicates_and_string_references_are_normalized(self):
        self.assertEqual(helper.references(["a", {"name": "a"}, {"name": "b"}]), ["a", "b"])

    def test_invalid_tracking_annotation_fails_without_removal(self):
        obj = account(["platform"])
        obj["metadata"]["annotations"][helper.OWNED] = '{"unexpected":true}'
        with self.assertRaises(ValueError):
            helper.plan(obj, [])


class FakeAPI:
    def __init__(self, obj):
        self.obj = copy.deepcopy(obj)
        self.calls = []
        self.conflicts = 0

    def request(self, method, path, body=None, content_type=None):
        self.calls.append((method, path, copy.deepcopy(body), content_type))
        if method == "GET":
            if self.obj is None:
                raise HTTPError(path, 404, "Not found", {}, io.BytesIO())
            return copy.deepcopy(self.obj)
        if self.conflicts:
            self.conflicts -= 1
            self.obj["imagePullSecrets"].append({"name": "rotated-platform"})
            self.obj["metadata"]["resourceVersion"] = "2"
            raise HTTPError(path, 409, "Conflict", {}, io.BytesIO())
        if method == "POST":
            self.obj = copy.deepcopy(body)
            self.obj["metadata"]["resourceVersion"] = "1"
        elif content_type == "application/json-patch+json":
            for operation in body:
                if operation["path"] == "/imagePullSecrets":
                    self.obj["imagePullSecrets"] = operation["value"]
                elif operation["path"].endswith("managed-pull-secrets"):
                    self.obj["metadata"]["annotations"][helper.OWNED] = operation["value"]
        return copy.deepcopy(self.obj)


class ReconcileTests(unittest.TestCase):
    target = {"name": "test-argus", "namespace": "test", "secrets": [{"name": "custom"}]}

    def test_shares_ownership_without_force_before_changing_list(self):
        api = FakeAPI(account(["platform"]))
        self.assertTrue(helper.reconcile(api, self.target, "test", "test"))
        apply = next(call for call in api.calls if call[3] == "application/apply-patch+yaml")
        self.assertNotIn("force", apply[1])
        self.assertEqual(apply[2]["imagePullSecrets"], [{"name": "platform"}])
        patch_call = next(call for call in api.calls if call[3] == "application/json-patch+json")
        self.assertEqual(patch_call[2][0]["op"], "test")
        self.assertEqual(helper.references(api.obj["imagePullSecrets"]), ["platform", "custom"])

    @patch.object(helper.time, "sleep")
    def test_concurrent_rotation_is_retried_from_latest_state(self, _):
        api = FakeAPI(account(["platform"]))
        api.conflicts = 1
        helper.reconcile(api, self.target, "test", "test")
        self.assertEqual(helper.references(api.obj["imagePullSecrets"]), ["platform", "rotated-platform", "custom"])

    def test_refuses_another_release_account(self):
        api = FakeAPI(account(["platform"]))
        with self.assertRaises(ValueError):
            helper.reconcile(api, self.target, "different-release", "test")
        self.assertTrue(all(call[0] == "GET" for call in api.calls))

    def test_runtime_does_not_recreate_deleted_accounts(self):
        api = FakeAPI(None)
        self.assertFalse(helper.reconcile(api, self.target, "test", "test"))
        self.assertEqual([call[0] for call in api.calls], ["GET"])

    def test_bootstrap_creates_account_with_credentials_before_workloads(self):
        api = FakeAPI(None)
        self.assertTrue(helper.reconcile(api, self.target, "test", "test", create=True))
        created = next(call[2] for call in api.calls if call[0] == "POST")
        self.assertEqual(created["imagePullSecrets"], [{"name": "custom"}])
        self.assertEqual(created["metadata"]["annotations"]["meta.helm.sh/release-name"], "test")


class PauseTests(unittest.TestCase):
    config = {"releaseNamespace": "test", "configName": "helper", "targets": []}

    def test_running_helper_acknowledges_pause_before_processing_old_configuration(self):
        newer = dict(self.config, targets=[{"name": "new-account"}])
        pending = helper.fingerprint(newer)
        api = Mock()
        api.request.return_value = {
            "metadata": {"resourceVersion": "1", "annotations": {helper.PAUSE: pending}},
            "data": {"targets.json": json.dumps(self.config)},
        }
        self.assertIsNone(helper.load_current(api, self.config))
        operation = api.request.call_args.args[2][-1]
        self.assertEqual(operation["value"], pending)
        self.assertTrue(operation["path"].endswith("pull-secrets-paused"))

    def test_running_helper_resumes_when_helm_publishes_requested_configuration(self):
        api = Mock()
        api.request.return_value = {
            "metadata": {"resourceVersion": "1", "annotations": {helper.PAUSE: helper.fingerprint(self.config)}},
            "data": {"targets.json": json.dumps(self.config)},
        }
        self.assertEqual(helper.load_current(api, self.config), self.config)
        self.assertEqual(api.request.call_count, 1)

    def test_fresh_install_does_not_wait_for_nonexistent_running_helper(self):
        api = Mock()
        api.request.side_effect = HTTPError("config", 404, "Not found", {}, io.BytesIO())
        helper.pause_current(api, self.config)
        self.assertEqual(api.request.call_count, 1)


if __name__ == "__main__":
    unittest.main()
