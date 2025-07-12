import os
import requests
import json
import time
from pathlib import Path

API_URL_BASE = os.environ.get("API_URL_BASE", "https://api.adoptium.net/v3/assets/feature_releases/21/ga")
IMAGE_TYPE = os.environ.get("IMAGE_TYPE", "sbom")
VENDOR = os.environ.get("VENDOR", "eclipse")
HEAP_SIZE = os.environ.get("HEAP_SIZE", "normal")
PAGE_SIZE = int(os.environ.get("PAGE_SIZE", "20"))
PROJECT_ROOT = os.environ.get("PROJECT_ROOT", "Temurin")
JAVA_VERSION = os.environ.get("JAVA_VERSION", "JDK 21")

def fetch_sboms():
    sbom_dir = Path("sboms")
    sbom_dir.mkdir(exist_ok=True)
    metadata = []

    page = 1
    before = None

    while True:
        print(f"Fetching page {page}...")
        params = {
            "image_type": IMAGE_TYPE,
            "vendor": VENDOR,
            "heap_size": HEAP_SIZE,
            "page_size": PAGE_SIZE
        }
        if before:
            params["before"] = before

        response = requests.get(API_URL_BASE, params=params)
        response.raise_for_status()
        data = response.json()

        if not data:
            print("No more results.")
            break

        stop = False 

        for asset in data:
            # we stop if the last asset is before the cutoff date
            release_date_str = asset["timestamp"]
            release_date = datetime.fromisoformat(release_date_str.replace("Z", "")).date()

            if release_date < cutoff_date:
                stop = True
                break   

            version = asset["version_data"]["semver"]
            for binary in asset.get("binaries", []):
                os_name = binary["os"]
                arch = binary["architecture"]
                sbom_url = binary.get("package", {}).get("link")

                if not sbom_url:
                    print(f"Skipping {version} ({os_name} {arch}) - no SBOM")
                    continue

                path = sbom_dir / f"{os_name}_{arch}_{version}" / "sbom.json"
                path.parent.mkdir(parents=True, exist_ok=True)
                print(f"Downloading SBOM for {os_name} {arch} {version}")
                sbom_resp = requests.get(sbom_url)
                sbom_resp.raise_for_status()
                path.write_text(sbom_resp.text)

                project_name = f"{PROJECT_ROOT} / {JAVA_VERSION} / {os_name} {arch} / jdk-{version}"
                metadata.append({
                    "path": str(path),
                    "projectName": project_name,
                    "projectVersion": version
                })
            
            if stop: 
                print(f"Stopping fetch as the last asset is before the cutoff date: {cutoff_date}")
                break

        before = data[-1]["timestamp"].split("T")[0]
        page += 1
        time.sleep(1)

    with open("metadata.json", "w") as f:
        json.dump(metadata, f, indent=2)
    print("Done. Wrote SBOMs and metadata.json.")

if __name__ == "__main__":
    fetch_sboms()
