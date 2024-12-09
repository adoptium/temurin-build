import json

with open("sample-metadata.json", "r") as metadata_file:
    with open("workspace/target/OpenJDK-sbom.json", "r") as sbom_file:
        metadata = json.loads(metadata_file.read())
        sbom = json.loads(sbom_file.read())
        if "metadata" not in sbom:
            sbom["metadata"] = {}
        if "properties" not in sbom["metadata"]:
            sbom["metadata"]["properties"] = []
        properties_to_skip = []
        for property in metadata:
            if property in properties_to_skip:
                continue
            sbom["metadata"]["properties"].append(
                {"name": property, "value": metadata[property]}
            )
        with open("sbom_modified.json", "w") as out:
            out.write(json.dumps(sbom, indent=True))
