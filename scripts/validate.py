#!/usr/bin/env python3
"""Run repository checks without obtaining cloud credentials or applying resources."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
TERRAFORM_ROOTS = (
    ".",
    "modules/rtsp-security-groups",
    "examples/https-alb",
    "examples/rtsp-tcp",
    "examples/rtsp-udp",
)
MOCK_TEST_ROOTS = (".", "modules/rtsp-security-groups")


def validation_environment(source: dict[str, str]) -> dict[str, str]:
    """Do not pass ambient AWS credentials or Terraform argument overrides."""
    result = {
        key: value
        for key, value in source.items()
        if not key.upper().startswith(("AWS_", "TF_CLI_ARGS", "TF_VAR_"))
    }
    result.update(
        TF_IN_AUTOMATION="true",
        TF_INPUT="false",
        AWS_EC2_METADATA_DISABLED="true",
    )
    return result


def terraform_commands(executable: str) -> list[list[str]]:
    """A fixed command allowlist: format, backend-free init, validate, mock test."""
    commands = [[executable, "fmt", "-check", "-recursive"]]
    for directory in TERRAFORM_ROOTS:
        prefix = [executable, f"-chdir={directory}"]
        commands.append(prefix + ["init", "-backend=false", "-input=false"])
        commands.append(prefix + ["validate", "-no-color"])
        if directory in MOCK_TEST_ROOTS:
            commands.append(prefix + ["test", "-no-color"])
    return commands


def execute(command: list[str], environment: dict[str, str]) -> None:
    print("+ " + " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, env=environment, check=True, timeout=900)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--terraform", default="terraform", help="Terraform executable path")
    parser.add_argument(
        "--contracts-only",
        action="store_true",
        help="Run only standard-library repository tests; no Terraform or downloads",
    )
    args = parser.parse_args()
    environment = validation_environment(dict(os.environ))
    try:
        execute([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"], environment)
        if not args.contracts_only:
            for command in terraform_commands(args.terraform):
                execute(command, environment)
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(f"Validation failed: {error}", file=sys.stderr)
        return 1
    print("Repository contracts passed." if args.contracts_only else "Repository and Terraform checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
