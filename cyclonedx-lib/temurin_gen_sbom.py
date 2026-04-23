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
Command line tool to construct a CycloneDX SBOM.
(Almost) 1:1 translation of TemurinGenSBOM.java using cyclonedx-python-lib.

TODO (CycloneDX 1.6): Formulation / workflow / attestation commands currently skip gracefully
because the Python library does not yet fully support CycloneDX 1.6
formulations.  Post-processing is handled by the separate
temporary_sbom_post_processing.py script.
"""

import hashlib
import json
import sys
import uuid

from cyclonedx.model import HashAlgorithm, HashType, Property, XsUri
from cyclonedx.model.bom import Bom, BomMetaData
from cyclonedx.model.component import Component, ComponentType
from cyclonedx.model.contact import OrganizationalContact, OrganizationalEntity
from cyclonedx.model.tool import ToolRepository
from cyclonedx.output import make_outputter
from cyclonedx.schema import OutputFormat, SchemaVersion

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
verbose = False
use_json = True  # default to JSON (matches Java behaviour when --jsonFile)

# ---------------------------------------------------------------------------
# File I/O helpers
# ---------------------------------------------------------------------------

def read_bom(file_name):
    """Read a CycloneDX BOM from a JSON file."""
    with open(file_name, "r", encoding="utf-8") as fh:
        return Bom.from_json(data=json.loads(fh.read()))


def write_bom(bom, file_name):
    """Write a CycloneDX BOM to JSON with standard key ordering."""
    outputter = make_outputter(
        bom,
        output_format=OutputFormat.JSON,
        schema_version=SchemaVersion.V1_6,
    )
    raw = json.loads(outputter.output_as_string())
    ordered = _reorder_cdx(raw)
    with open(file_name, "w", encoding="utf-8") as fh:
        json.dump(ordered, fh, indent=2, ensure_ascii=False)
        fh.write("\n")


# ---------------------------------------------------------------------------
# Hardcoded JSON key ordering explicitly hardcoded to match the legacy Java (Jackson) output.
# ---------------------------------------------------------------------------

_CDX_KEY_ORDER = {
    "bom": ["$schema", "bomFormat", "specVersion", "serialNumber", "version",
            "metadata", "components", "services", "externalReferences",
            "dependencies", "compositions", "vulnerabilities", "formulation"],
    "metadata": ["timestamp", "lifecycles", "tools", "authors", "component",
                 "manufacture", "supplier", "properties"],
    "component": ["type", "mime-type", "bom-ref", "supplier", "manufacturer",
                  "group", "name", "version", "description", "scope",
                  "author", "publisher", "hashes", "licenses", "copyright",
                  "cpe", "purl", "swid", "pedigree", "externalReferences",
                  "properties", "components", "evidence", "releaseNotes"],
    "tools": ["components", "services"],
    "hash": ["alg", "content"],
    "property": ["name", "value"],
    "dependency": ["ref", "dependsOn"],
    "contact": ["name", "email", "phone"],
    "org": ["name", "url", "contact"],
}

_CDX_CHILD_CTX = {
    "metadata": "metadata", "tools": "tools", "component": "component",
    "components": "component", "hashes": "hash", "properties": "property",
    "dependencies": "dependency", "authors": "contact",
    "manufacture": "org", "supplier": "org",
}


def _reorder_cdx(obj, ctx="bom"):
    """Recursively reorder JSON keys to match CycloneDX schema order."""
    if isinstance(obj, list):
        return [_reorder_cdx(item, ctx) for item in obj]
    if not isinstance(obj, dict):
        return obj
    order = _CDX_KEY_ORDER.get(ctx, [])
    order_set = set(order)
    sorted_keys = [k for k in order if k in obj] + [k for k in obj if k not in order_set]
    return {k: _reorder_cdx(obj[k], _CDX_CHILD_CTX.get(k, ctx)) for k in sorted_keys}


# ---------------------------------------------------------------------------
# BOM manipulation functions  (mirror the Java static methods)
# ---------------------------------------------------------------------------

def create_bom():
    bom = Bom(serial_number=uuid.uuid4())
    return bom


def add_metadata(file_name):
    bom = read_bom(file_name)
    org = OrganizationalEntity(
        name="Eclipse Foundation",
        urls=[XsUri("https://www.eclipse.org/")],
    )
    bom.metadata.manufacture = org
    author = OrganizationalContact(name="Adoptium Temurin")
    bom.metadata.authors.add(author)
    return bom


def add_metadata_component(file_name, name, comp_type, version, description):
    bom = read_bom(file_name)
    type_map = {
        "os": ComponentType.OPERATING_SYSTEM,
    }
    ct = type_map.get(comp_type, ComponentType.FRAMEWORK)
    comp = Component(
        name=name,
        type=ct,
        version=version,
        description=description,
    )
    bom.metadata.component = comp
    bom.register_dependency(comp, [])
    return bom


def add_metadata_property(file_name, name, value):
    bom = read_bom(file_name)
    bom.metadata.properties.add(Property(name=name, value=value))
    return bom


def add_metadata_tools(file_name, tool_name, version):
    bom = read_bom(file_name)
    tool_comp = Component(
        name=tool_name,
        type=ComponentType.APPLICATION,
        version=version,
    )
    # ToolRepository.components is a SortedSet; add to it.
    bom.metadata.tools.components.add(tool_comp)
    return bom


def add_component(file_name, comp_name, version, description):
    bom = read_bom(file_name)
    comp = Component(
        name=comp_name,
        version=version,
        type=ComponentType.FRAMEWORK,
        description=description,
        group="adoptium.net",
        author="Eclipse Temurin",
        publisher="Eclipse Temurin",
    )
    bom.components.add(comp)
    bom.register_dependency(comp, [])
    if bom.metadata.component is not None:
        bom.register_dependency(bom.metadata.component, [comp])
    return bom


def add_component_hash(file_name, comp_name, hash_value):
    bom = read_bom(file_name)
    for item in bom.components:
        if item.name == comp_name:
            item.hashes.add(
                HashType(alg=HashAlgorithm.SHA_256, content=hash_value)
            )
    return bom


def add_component_property(file_name, comp_name, name, value):
    bom = read_bom(file_name)
    for item in bom.components:
        if item.name == comp_name:
            item.properties.add(Property(name=name, value=value))
    return bom


# ---------------------------------------------------------------------------
# TODO (CycloneDX 1.6):
# Formulation stubs (not natively supported by cyclonedx-python-lib yet)
# Actual formulation injection is done by temporary_sbom_post_processing.py.
# When native support arrives, replace these stubs with real implementations.
# ---------------------------------------------------------------------------

def _skip_formulation(label, **_kw):
    print(f"SKIP (Python lib): {label} — formulations not yet supported by cyclonedx-python-lib")


def add_sbom_dependency_versions(file_name):
    """Record the Python SBOM toolchain versions and their SHA-256 hashes as
    metadata properties.  This replaces the old addCycloneDXVersions() bash
    function that iterated over Java JAR files."""
    import importlib.metadata as ilm

    bom = read_bom(file_name)

    # Iterate all installed distributions in this environment (the SBOM venv)
    seen = set()
    for dist in ilm.distributions():
        pkg_name = dist.metadata["Name"]
        if pkg_name in seen:
            continue
        seen.add(pkg_name)
        pkg_version = dist.metadata["Version"]
        bom.metadata.properties.add(
            Property(name=f"sbom:tool:{pkg_name}:version", value=pkg_version)
        )
        # Compute a combined hash of every file the package installed
        if dist.files:
            h = hashlib.sha256()
            for f in sorted(dist.files):
                full = dist.locate_file(f)
                if full.is_file():
                    h.update(full.read_bytes())
            bom.metadata.properties.add(
                Property(name=f"sbom:tool:{pkg_name}:sha256", value=h.hexdigest())
            )
    return bom


def add_component_file_hash(file_name, comp_name, file_path):
    """Calculate SHA-256 of *file_path* and attach it to the named component."""
    import pathlib
    target = pathlib.Path(file_path)
    if not target.is_file():
        print(f"WARNING: File not found for hashing: {file_path}")
        return read_bom(file_name)
    h = hashlib.sha256()
    with open(target, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return add_component_hash(file_name, comp_name, h.hexdigest())


# ---------------------------------------------------------------------------
# CLI argument parser  (mirrors the Java parseArgs exactly)
# ---------------------------------------------------------------------------

def parse_args(argv):
    global verbose, use_json
    args = {
        "cmd": "",
        "file_name": None,
        "name": None,
        "value": None,
        "version": None,
        "comp_name": None,
        "description": None,
        "type": None,
        "tool": None,
        "hash": None,
        "formula_name": None,
        "formula_prop_name": None,
        "workflow_ref": None,
        "workflow_uid": None,
        "workflow_name": None,
        "workflow_step_name": None,
        "task_types": None,
        "executed": None,
        "file_path": None,
    }

    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--jsonFile":
            i += 1; args["file_name"] = argv[i]; use_json = True
        elif a == "--xmlFile":
            i += 1; args["file_name"] = argv[i]; use_json = False
        elif a == "--version":
            i += 1; args["version"] = argv[i]
        elif a == "--name":
            i += 1; args["name"] = argv[i]
        elif a == "--value":
            i += 1; args["value"] = argv[i]
        elif a == "--hash":
            i += 1; args["hash"] = argv[i]
        elif a == "--compName":
            i += 1; args["comp_name"] = argv[i]
        elif a == "--formulaName":
            i += 1; args["formula_name"] = argv[i]
        elif a == "--description":
            i += 1; args["description"] = argv[i]
        elif a == "--type":
            i += 1; args["type"] = argv[i]
        elif a == "--tool":
            i += 1; args["tool"] = argv[i]
        elif a == "--formulaPropName":
            i += 1; args["formula_prop_name"] = argv[i]
        elif a == "--workflowRef":
            i += 1; args["workflow_ref"] = argv[i]
        elif a == "--workflowName":
            i += 1; args["workflow_name"] = argv[i]
        elif a == "--workflowUid":
            i += 1; args["workflow_uid"] = argv[i]
        elif a == "--taskTypes":
            i += 1; args["task_types"] = argv[i]
        elif a == "--workflowStepName":
            i += 1; args["workflow_step_name"] = argv[i]
        elif a == "--executed":
            i += 1; args["executed"] = argv[i]
        elif a == "--createNewSBOM":
            args["cmd"] = "createNewSBOM"
        elif a == "--addMetadata":
            args["cmd"] = "addMetadata"
        elif a == "--addMetadataComponent":
            args["cmd"] = "addMetadataComponent"
        elif a == "--addMetadataProp":
            args["cmd"] = "addMetadataProperty"
        elif a == "--addComponent":
            args["cmd"] = "addComponent"
        elif a == "--addComponentHash":
            args["cmd"] = "addComponentHash"
        elif a == "--addComponentProp":
            args["cmd"] = "addComponentProp"
        elif a == "--addMetadataTools":
            args["cmd"] = "addMetadataTools"
        elif a == "--addFormulation":
            args["cmd"] = "addFormulation"
        elif a == "--addFormulationComp":
            args["cmd"] = "addFormulationComp"
        elif a == "--addFormulationCompProp":
            args["cmd"] = "addFormulationCompProp"
        elif a == "--addFormulaProp":
            args["cmd"] = "addFormulaProp"
        elif a == "--addWorkflow":
            args["cmd"] = "addWorkflow"
        elif a == "--addWorkflowStep":
            args["cmd"] = "addWorkflowStep"
        elif a == "--addWorkflowStepCmd":
            args["cmd"] = "addWorkflowStepCmd"
        elif a == "--addSBOMDependencyVersions":
            args["cmd"] = "addSBOMDependencyVersions"
        elif a == "--addComponentFileHash":
            args["cmd"] = "addComponentFileHash"
        elif a == "--filePath":
            i += 1; args["file_path"] = argv[i]
        elif a == "--verbose":
            verbose = True
        i += 1

    return args


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

def dispatch(args):
    cmd = args["cmd"]
    fn = args["file_name"]

    if cmd == "createNewSBOM":
        return create_bom()

    elif cmd == "addMetadata":
        return add_metadata(fn)

    elif cmd == "addMetadataComponent":
        return add_metadata_component(
            fn, args["name"], args["type"], args["version"], args["description"]
        )

    elif cmd == "addMetadataProperty":
        return add_metadata_property(fn, args["name"], args["value"])

    elif cmd == "addMetadataTools":
        return add_metadata_tools(fn, args["tool"], args["version"])

    elif cmd == "addComponent":
        return add_component(
            fn, args["comp_name"], args["version"], args["description"]
        )

    elif cmd == "addComponentHash":
        return add_component_hash(fn, args["comp_name"], args["hash"])

    elif cmd == "addComponentProp":
        return add_component_property(
            fn, args["comp_name"], args["name"], args["value"]
        )

    # --- Formulation: skip old granular commands gracefully ---
    elif cmd == "addFormulation":
        _skip_formulation("addFormulation", formula_name=args["formula_name"])
        return None

    elif cmd == "addFormulationComp":
        _skip_formulation("addFormulationComp", formula_name=args["formula_name"], name=args["name"])
        return None

    elif cmd == "addFormulationCompProp":
        _skip_formulation("addFormulationCompProp", formula_name=args["formula_name"], comp_name=args["comp_name"])
        return None

    elif cmd == "addFormulaProp":
        _skip_formulation("addFormulaProp", formula_name=args["formula_name"])
        return None

    elif cmd == "addWorkflow":
        _skip_formulation("addWorkflow", workflow_ref=args["workflow_ref"])
        return None

    elif cmd == "addWorkflowStep":
        _skip_formulation("addWorkflowStep", workflow_ref=args["workflow_ref"])
        return None

    elif cmd == "addWorkflowStepCmd":
        _skip_formulation("addWorkflowStepCmd", workflow_ref=args["workflow_ref"])
        return None

    elif cmd == "addSBOMDependencyVersions":
        return add_sbom_dependency_versions(fn)

    elif cmd == "addComponentFileHash":
        return add_component_file_hash(fn, args["comp_name"], args.get("file_path", ""))

    else:
        print(" ".join(sys.argv[1:]))
        print("\nPlease enter a valid command.")
        sys.exit(1)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    args = parse_args(sys.argv[1:])

    try:
        bom = dispatch(args)
        if bom is not None:
            write_bom(bom, args["file_name"])
    except Exception as e:
        print(" ".join(sys.argv[1:]))
        print(f"\nException: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
