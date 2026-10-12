"""Offline repository guardrails, not a substitute for Terraform/provider tests."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import re
import subprocess
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("connectivity_validation", ROOT / "scripts" / "validate.py")
assert SPEC is not None and SPEC.loader is not None
VALIDATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATION)


class ValidationRunnerTests(unittest.TestCase):
    def test_command_allowlist_has_no_cloud_mutations(self):
        commands = VALIDATION.terraform_commands("terraform")
        self.assertEqual(commands[0], ["terraform", "fmt", "-check", "-recursive"])
        permitted = {"fmt", "init", "validate", "test"}
        for command in commands:
            verbs = [part for part in command[1:] if not part.startswith("-")]
            self.assertEqual(len(verbs), 1)
            self.assertIn(verbs[0], permitted)
            self.assertNotIn("apply", command)
            self.assertNotIn("destroy", command)
            self.assertNotIn("plan", command)

    def test_every_terraform_root_is_initialized_without_backend_and_validated(self):
        commands = VALIDATION.terraform_commands("terraform")
        for directory in VALIDATION.TERRAFORM_ROOTS:
            self.assertIn(["terraform", f"-chdir={directory}", "init", "-backend=false", "-input=false"], commands)
            self.assertIn(["terraform", f"-chdir={directory}", "validate", "-no-color"], commands)
        self.assertEqual(len(VALIDATION.TERRAFORM_ROOTS), 5)

    def test_only_mock_provider_roots_are_tested(self):
        commands = VALIDATION.terraform_commands("terraform")
        test_commands = [command for command in commands if "test" in command]
        self.assertEqual(test_commands, [
            ["terraform", "-chdir=.", "test", "-no-color"],
            ["terraform", "-chdir=modules/rtsp-security-groups", "test", "-no-color"],
        ])
        for directory in VALIDATION.MOCK_TEST_ROOTS:
            files = sorted((ROOT / directory / "tests").glob("*.tftest.hcl"))
            self.assertTrue(files, f"No native tests in {directory}")
            for path in files:
                text = path.read_text(encoding="utf-8")
                self.assertRegex(text, r'(?m)^mock_provider\s+"aws"\s*\{')
                self.assertNotRegex(text, r'(?m)^provider\s+"aws"\s*\{')

    def test_environment_drops_ambient_credentials_and_cli_overrides(self):
        result = VALIDATION.validation_environment({
            "AWS_ACCESS_KEY_ID": "example-not-a-key",
            "aws_secret_access_key": "example-not-a-secret",
            "AWS_PROFILE": "do-not-load",
            "TF_CLI_ARGS_init": "-backend=true",
            "TF_VAR_foundry_source_cidrs": '["0.0.0.0/0"]',
            "PATH": "keep-path",
        })
        self.assertEqual(result, {
            "PATH": "keep-path", "TF_IN_AUTOMATION": "true", "TF_INPUT": "false",
            "AWS_EC2_METADATA_DISABLED": "true",
        })

    def test_failed_subprocess_is_not_ignored(self):
        with mock.patch.object(VALIDATION.subprocess, "run", side_effect=subprocess.CalledProcessError(1, ["terraform"])) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                VALIDATION.execute(["terraform", "validate"], {})
            self.assertTrue(run.call_args.kwargs["check"])
            self.assertEqual(run.call_args.kwargs["cwd"], ROOT)
            self.assertNotIn("shell", run.call_args.kwargs)


class RepositorySecurityTests(unittest.TestCase):
    def setUp(self):
        self.workflow = (ROOT / ".github" / "workflows" / "validate.yml").read_text(encoding="utf-8")

    def test_workflow_only_validates_and_has_read_only_permissions(self):
        self.assertIn("  contents: read", self.workflow)
        self.assertIn("  pull_request:", self.workflow)
        self.assertIn("  workflow_dispatch:", self.workflow)
        self.assertIn("    branches: [main]", self.workflow)
        self.assertNotRegex(self.workflow, r"(?i)secrets\.|id-token|pull_request_target|contents:\s*write|continue-on-error")
        self.assertEqual(re.findall(r"(?m)^\s+run:\s*(.+)$", self.workflow), ["python scripts/validate.py"])
        self.assertEqual(sorted(path.name for path in (ROOT / ".github" / "workflows").glob("*")), ["validate.yml"])

    def test_workflow_actions_are_commit_pinned_and_checkout_drops_credentials(self):
        actions = re.findall(r"(?m)^\s+- uses:\s+(\S+)", self.workflow)
        self.assertEqual(len(actions), 3)
        for action in actions:
            self.assertRegex(action, r"^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+@[a-f0-9]{40}$")
        self.assertIn("persist-credentials: false", self.workflow)
        self.assertIn("terraform_version: 1.9.8", self.workflow)
        self.assertIn("terraform_wrapper: false", self.workflow)
        self.assertIn("timeout-minutes: 20", self.workflow)

    def test_no_literal_credentials_in_source_or_examples(self):
        patterns = (
            r"AKIA[A-Z0-9]{16}",
            r"(?:gh[pousr]_|github_pat_)[A-Za-z0-9_]{30,}",
            r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
            r'(?im)^\s*(?:access_key|secret_key|aws_access_key_id|aws_secret_access_key)\s*=\s*"[^"\n]+"',
        )
        candidates = [path for path in ROOT.rglob("*") if path.is_file()
                      and not any(part in {".git", ".terraform", "__pycache__"} for part in path.relative_to(ROOT).parts)
                      and (path.suffix in {".tf", ".hcl", ".yml", ".yaml", ".py", ".md"} or path.name.endswith(".tfvars.example"))]
        self.assertTrue(candidates)
        for path in candidates:
            content = path.read_text(encoding="utf-8")
            for pattern in patterns:
                self.assertNotRegex(content, pattern, str(path.relative_to(ROOT)))

    def test_published_tfvars_samples_are_not_world_open(self):
        samples = sorted((ROOT / "examples").rglob("*.tfvars.example"))
        self.assertEqual(len(samples), 3)
        for path in samples:
            content = path.read_text(encoding="utf-8")
            self.assertNotIn('"0.0.0.0/0"', content)
            self.assertNotIn('"::/0"', content)


if __name__ == "__main__":
    unittest.main()
