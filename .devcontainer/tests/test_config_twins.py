#!/usr/bin/env python3
# Run:     python3 .devcontainer/tests/test_config_twins.py
# Inputs:  .devcontainer/devcontainer.json (YOLO) and
#          .devcontainer/normie/devcontainer.json (normie), parsed as JSONC with
#          .host/dc-resolve.py's comment stripper.
# Outputs: unittest results. Fails unless each file carries its mode's posture
#          and the two differ in nothing else but the name and the paths that
#          are relative to the file's own folder. Comments are not compared.

import copy
import importlib.machinery
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
YOLO = ROOT / ".devcontainer" / "devcontainer.json"
NORMIE = ROOT / ".devcontainer" / "normie" / "devcontainer.json"
PACKAGE_TARGETS = ("/opt/R/", "/opt/venv", "/usr/local/texlive")
POSTURE = {
    "yolo": {"seccomp": "builtin", "readonly": "true", "internet": "firewalled"},
    "normie": {"seccomp": "unconfined", "readonly": "false", "internet": "open"},
}


def load_resolver():
    path = ROOT / ".host" / "dc-resolve.py"
    loader = importlib.machinery.SourceFileLoader("dc_resolve_under_test", str(path))
    spec = importlib.util.spec_from_loader("dc_resolve_under_test", loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


STRIP = load_resolver().strip_jsonc


def load(path):
    return json.loads(STRIP(path.read_text(encoding="utf-8")))


def posture(config):
    seccomp = [arg.split("=", 2)[2] for arg in config["runArgs"] if arg.startswith("--security-opt=seccomp=")]
    readonly = {
        mount.rsplit("readonly=", 1)[1]
        for mount in config["mounts"]
        if any(f"target={target}" in mount for target in PACKAGE_TARGETS)
    }
    package_mounts = [m for m in config["mounts"] if any(f"target={t}" in m for t in PACKAGE_TARGETS)]
    return {
        "seccomp": seccomp[0] if len(seccomp) == 1 else seccomp,
        "readonly": readonly.pop() if len(readonly) == 1 and len(package_mounts) == 3 else readonly,
        "internet": config["containerEnv"].get("SANDBOX_INTERNET"),
    }


def neutralize(config):
    """The config with every intended difference blanked out."""
    config = copy.deepcopy(config)
    config["name"] = None
    config["build"]["dockerfile"] = None
    config["build"]["context"] = None
    config["runArgs"] = [None if arg.startswith("--security-opt=seccomp=") else arg for arg in config["runArgs"]]
    config["mounts"] = [
        mount.rsplit("readonly=", 1)[0] if any(f"target={t}" in mount for t in PACKAGE_TARGETS) else mount
        for mount in config["mounts"]
    ]
    config["containerEnv"]["SANDBOX_INTERNET"] = None
    return config


class ConfigTwinTests(unittest.TestCase):
    def setUp(self):
        self.yolo = load(YOLO)
        self.normie = load(NORMIE)

    def test_each_file_carries_its_posture(self):
        self.assertEqual(posture(self.yolo), POSTURE["yolo"])
        self.assertEqual(posture(self.normie), POSTURE["normie"])

    def test_no_posture_comes_from_the_host_environment(self):
        for path in (YOLO, NORMIE):
            self.assertNotIn("localEnv:SANDBOX_", path.read_text(encoding="utf-8"), path)

    def test_names_tell_the_modes_apart(self):
        self.assertEqual(self.normie["name"], self.yolo["name"] + " (normie)")

    def test_build_resolves_to_the_same_dockerfile_and_context(self):
        for path, config in ((YOLO, self.yolo), (NORMIE, self.normie)):
            build = config["build"]
            self.assertEqual((path.parent / build["dockerfile"]).resolve(), ROOT / ".devcontainer" / "Dockerfile")
            self.assertEqual((path.parent / build["context"]).resolve(), ROOT)

    def test_nothing_else_differs(self):
        self.assertEqual(neutralize(self.yolo), neutralize(self.normie))

    def test_shared_volumes_are_not_keyed_by_config(self):
        for mount in self.yolo["mounts"]:
            self.assertNotIn("devcontainerId", mount)


if __name__ == "__main__":
    unittest.main()
