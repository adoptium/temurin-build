#!/usr/bin/env python3
# ********************************************************************************
# Copyright (c) 2024 Contributors to the Eclipse Foundation
#
# See the NOTICE file(s) with this work for additional
# information regarding copyright ownership.
#
# This program and the accompanying materials are made
# available under the terms of the Apache Software License 2.0
# which is available at https://www.apache.org/licenses/LICENSE-2.0.
#
# SPDX-License-Identifier: Apache-2.0
# ********************************************************************************

"""
TEMPORARY post-processing script for CycloneDX 1.6 formulation injection.

cyclonedx-python-lib does not yet support the CycloneDX 1.6 formulation array
(workflows, taskTypes, steps, commands).  This standalone script works around
that limitation by loading the finished SBOM JSON, appending the formulation
structures, and saving it back.

MIGRATION (once native formulation support arrives in cyclonedx-python-lib):
   1. Delete cyclonedx-lib/temporary_sbom_post_processing.py
   2. Update everything marked with TODO (CycloneDX 1.6) back to the correct state
   3. Implement native formulation logic (--addWorkflow, --addWorkflowStep,
      --addWorkflowStepCmd) in cyclonedx-lib/temurin_gen_sbom.py, replacing
      the _skip_formulation() stubs with real CycloneDX lib calls.
   4. The addSBOMWorkflow/Step/Cmd calls in addTemurinBuildRecipeToSBOM and
      addReproducibleVerificationRecipeToSBOM will then work natively.
   5. Delete this entire block (down to "END TEMPORARY")
"""

import argparse
import json
import sys


def build_formulation_build_recipe(args):
    """Build the 'Temurin Build Script' formulation entry."""

    steps = [
        {
            "name": "clone repo",
            "description": "clone repository",
            "commands": [
                {"executed": f"git clone {args.clone_url}"}
            ],
        },
        {
            "name": "cd into repository",
            "description": "cd into temurin-build and checkout commit",
            "commands": [
                {"executed": f"cd {args.repo_name}"},
                {"executed": f"git checkout {args.sha}"},
            ],
        },
        {
            "name": "makejdk",
            "description": "execute makejdk-any-platform.sh",
            "commands": [
                {"executed": args.makejdk_cmd}
            ],
        },
    ]

    return {
        "bom-ref": f"formula_temurin_build_script_{args.full_ver}",
        "workflows": [
            {
                "bom-ref": f"workflow_temurin_build_script_{args.full_ver}",
                "uid": f"workflow_temurin_build_script_{args.full_ver}",
                "name": "Temurin Build Script",
                "taskTypes": ["clone", "build"],
                "steps": steps,
            }
        ],
    }


def build_formulation_repro_verification(args):
    """Build the 'Temurin Reproducible Verification' formulation entry."""

    steps = [
        {
            "name": "clone repo",
            "description": "clone repository",
            "commands": [
                {"executed": "git clone https://github.com/adoptium/temurin-build.git"}
            ],
        },
        {
            "name": "execute verification",
            "description": "run reproducible build compare script",
            "commands": [
                {"executed": args.verify_cmd}
            ],
        },
    ]

    return {
        "bom-ref": f"formula_temurin_reproducible_verification_{args.full_ver}",
        "workflows": [
            {
                "bom-ref": f"workflow_temurin_reproducible_verification_{args.full_ver}",
                "uid": f"workflow_temurin_reproducible_verification_{args.full_ver}",
                "name": "Temurin Reproducible Verification",
                "taskTypes": ["clone", "test"],
                "steps": steps,
            }
        ],
    }


def main():
    parser = argparse.ArgumentParser(
        description="Temporary CycloneDX 1.6 formulation post-processor. "
                    "Injects build recipe and reproducible verification "
                    "workflows into an existing SBOM JSON file."
    )
    parser.add_argument(
        "--sbom-json", required=True,
        help="Path to the SBOM JSON file to post-process.",
    )
    parser.add_argument(
        "--full-ver", required=True,
        help="Full JDK version string (e.g. 21.0.3+9).",
    )
    parser.add_argument(
        "--clone-url", required=True,
        help="Git clone URL for the temurin-build repository.",
    )
    parser.add_argument(
        "--sha", required=True,
        help="Git commit SHA to checkout.",
    )
    parser.add_argument(
        "--repo-name", required=True,
        help="Repository directory name (e.g. temurin-build).",
    )
    parser.add_argument(
        "--makejdk-cmd", required=True,
        help="Full makejdk-any-platform.sh command string.",
    )
    parser.add_argument(
        "--os-prefix", required=True, choices=["linux", "macos", "windows"],
        help="OS prefix for the reproducible verification script path.",
    )
    parser.add_argument(
        "--verify-cmd", required=True,
        help="Full reproducible verification command string.",
    )

    args = parser.parse_args()

    # Load the existing SBOM JSON
    try:
        with open(args.sbom_json, "r", encoding="utf-8") as fh:
            sbom = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"ERROR: Failed to load SBOM JSON '{args.sbom_json}': {exc}",
              file=sys.stderr)
        sys.exit(1)

    # Build both formulation entries
    build_recipe = build_formulation_build_recipe(args)
    repro_recipe = build_formulation_repro_verification(args)

    # Safely append to existing formulation array or create a new one
    if "formulation" in sbom and isinstance(sbom["formulation"], list):
        sbom["formulation"].append(build_recipe)
        sbom["formulation"].append(repro_recipe)
    else:
        sbom["formulation"] = [build_recipe, repro_recipe]

    # Write back with nice indentation
    try:
        with open(args.sbom_json, "w", encoding="utf-8") as fh:
            json.dump(sbom, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
    except OSError as exc:
        print(f"ERROR: Failed to write SBOM JSON '{args.sbom_json}': {exc}",
              file=sys.stderr)
        sys.exit(1)

    print(f"Formulation post-processing complete: {args.sbom_json}")


if __name__ == "__main__":
    main()
