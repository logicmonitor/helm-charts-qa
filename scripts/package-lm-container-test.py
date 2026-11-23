#!/usr/bin/env python3
"""Package local lm-container sources and refresh their cached subcharts."""

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="/private/tmp/lm-container-helm4-test")
    parser.add_argument("--helm", default="helm")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = Path(arguments.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="lm-container-package-") as directory:
        staging = Path(directory)
        for chart in ("lmutil", "argus", "collectorset-controller", "lm-container"):
            shutil.copytree(root / "charts" / chart, staging / chart,
                            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))

        def package(chart, destination):
            before = set(destination.glob("*.tgz"))
            result = subprocess.run([arguments.helm, "package", str(chart), "--destination", str(destination)],
                                    check=True, capture_output=True, text=True)
            print(result.stdout.strip())
            candidates = set(destination.glob("*.tgz")) - before
            if not candidates:
                candidates = set(destination.glob(chart.name + "-*.tgz"))
            return max(candidates, key=lambda path: path.stat().st_mtime)

        artifacts = staging / "artifacts"
        artifacts.mkdir()
        library = package(staging / "lmutil", artifacts)
        umbrella_deps = staging / "lm-container" / "charts"
        umbrella_deps.mkdir(exist_ok=True)
        refreshed = []
        for chart in ("argus", "collectorset-controller"):
            dependencies = staging / chart / "charts"
            dependencies.mkdir(exist_ok=True)
            for old in dependencies.glob("lmutil-*.tgz"):
                old.unlink()
            shutil.copy2(library, dependencies / library.name)
            artifact = package(staging / chart, artifacts)
            for old in umbrella_deps.glob(chart + "-*.tgz"):
                old.unlink()
            shutil.copy2(artifact, umbrella_deps / artifact.name)
            refreshed.append((chart, "lmutil", library))
            refreshed.append(("lm-container", chart, artifact))
        for old in umbrella_deps.glob("lmutil-*.tgz"):
            old.unlink()
        shutil.copy2(library, umbrella_deps / library.name)
        ksm = package(staging / "lm-container" / "vendor" / "kube-state-metrics", umbrella_deps)
        package(staging / "lm-container", output)
        refreshed.extend([
            ("lm-container", "lmutil", library),
            ("lm-container", "kube-state-metrics", ksm),
        ])
        for chart, dependency, artifact in refreshed:
            destination = root / "charts" / chart / "charts"
            destination.mkdir(exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=destination, suffix=".tmp", delete=False) as temporary:
                temporary_path = Path(temporary.name)
            try:
                shutil.copy2(artifact, temporary_path)
                temporary_path.replace(destination / artifact.name)
            finally:
                temporary_path.unlink(missing_ok=True)
            for old in destination.glob(dependency + "-*.tgz"):
                if old.name != artifact.name:
                    old.unlink()
        print("Refreshed local dependency caches for Argus, CSC, and lm-container.")


if __name__ == "__main__":
    main()
