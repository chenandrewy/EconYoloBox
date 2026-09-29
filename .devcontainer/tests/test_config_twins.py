#!/usr/bin/env python3
# Run:     python3 .devcontainer/tests/test_config_twins.py
# Inputs:  .devcontainer/devcontainer.json (YOLO) and
#          .devcontainer/normie/devcontainer.json (normie), parsed as JSONC with
#          .devcontainer/host/dc-resolve.py's comment stripper.
# Outputs: unittest results. Fails unless each file carries its mode's posture
#          and the two differ only in declared mode-specific behavior: name,
#          extension installation, mount access, window title and relative
#          build paths. Comments are not compared.

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
EXTENSION_TARGET = "/home/ubuntu/.vscode-server/extensions"
POSTURE = {
    "yolo": {"mode": "yolo", "seccomp": "builtin", "readonly": "true", "internet": "firewalled"},
    "normie": {"mode": "normie", "seccomp": "unconfined", "readonly": "false", "internet": "open"},
}


def load_resolver():
    path = ROOT / ".devcontainer" / "host" / "dc-resolve.py"
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
        "internet": config["containerEnv"].get("YOLOBOX_INTERNET"),
        "mode": config["containerEnv"].get("YOLOBOX_MODE"),
    }


def neutralize(config):
    """The config with every intended difference blanked out."""
    config = copy.deepcopy(config)
    config["name"] = None
    settings = config["customizations"]["vscode"]["settings"]
    settings["window.title"] = settings["window.title"].removeprefix("normie:")
    config["build"]["dockerfile"] = None
    config["build"]["context"] = None
    config["runArgs"] = [None if arg.startswith("--security-opt=seccomp=") else arg for arg in config["runArgs"]]
    config["mounts"] = [
        mount.rsplit("readonly=", 1)[0] if any(f"target={t}" in mount for t in (*PACKAGE_TARGETS, EXTENSION_TARGET)) else mount
        for mount in config["mounts"]
    ]
    config["containerEnv"]["YOLOBOX_INTERNET"] = None
    config["containerEnv"]["YOLOBOX_MODE"] = None
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
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("localEnv:YOLOBOX_", text, path)
            self.assertNotIn("localEnv:SANDBOX_", text, path)

    def test_names_tell_the_modes_apart(self):
        self.assertEqual(self.normie["name"], self.yolo["name"] + " (normie)")

    def test_normie_window_title_leads_with_the_mode(self):
        title = self.yolo["customizations"]["vscode"]["settings"]["window.title"]
        self.assertEqual(self.normie["customizations"]["vscode"]["settings"]["window.title"], "normie:" + title)

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

    def test_vscode_extensions_use_one_managed_volume(self):
        target = f"target={EXTENSION_TARGET},type=volume"
        source = "source=${localWorkspaceFolderBasename}-vscode-extensions-managed"
        for config, readonly in ((self.yolo, "true"), (self.normie, "false")):
            matches = [mount for mount in config["mounts"] if target in mount]
            self.assertEqual(matches, [f"{source},{target},readonly={readonly}"])
            settings = config["customizations"]["vscode"]["settings"]
            self.assertNotIn("remote.downloadExtensionsLocally", settings)
            self.assertFalse(settings["extensions.autoUpdate"])
            self.assertFalse(settings["extensions.autoCheckUpdates"])
        self.assertEqual(self.yolo["customizations"]["vscode"]["extensions"], [])
        self.assertEqual(self.normie["customizations"]["vscode"]["extensions"], [])


if __name__ == "__main__":
    unittest.main()
