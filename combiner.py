import json

with open("sample-metadata.json", "r") as metadata_file:
    with open("workspace/target/OpenJDK-sbom.json", "r") as sbom_file:
        metadata = json.loads(metadata_file.read())
        sbom = json.loads(sbom_file.read())
        if "metadata" not in sbom:
            sbom["metadata"] = {}
        if "properties" not in sbom["metadata"]:
            sbom["metadata"]["properties"] = []
        properties_to_skip = [
            "version"
        ]  # todo: do we flatten this? or put it somewhere else in some meaningful way? cyclone dx wasn't expecting a dict
        properties_to_flatten = [
            ""
        ]  # todo: BUILD_CONFIGURATION_param - are these redundant/should we just skip this, or is this what andrew means we should add to that bash script arg
        for property in metadata:
            if property in properties_to_skip:
                continue
            if property in properties_to_flatten:
                for sub in metadata[property]:
                    sbom["metadata"]["properties"].append(
                        {"name": sub, "value": json.dumps(metadata[property])}
                    )
            print(property)
            print(metadata[property])
            print("\n\n\n")
            sbom["metadata"]["properties"].append(
                {"name": property, "value": metadata[property]}
            )
        with open("sbom_modified.json", "w") as out:
            out.write(json.dumps(sbom, indent=True))
