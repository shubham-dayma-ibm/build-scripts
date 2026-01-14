import requests
import re
from openpyxl import Workbook

BASE_URL = "https://wheels.developerfirst.ibm.com/ppc64le/linux/"
HEADERS = {
    "Accept": "application/json",
    "User-Agent": "insomnia/11.0.1",
    "content-type": "multipart/form-data; boundary=---011000010111000001101001"
}
PAYLOAD = "-----011000010111000001101001--\r\n\r\n"


def get_python_version_from_wheel(og_filename: str) -> str:
    """
    Identify python version from wheel filename
    """
    if "abi3" in og_filename:
        return "abi3"
    else:
        match = re.search(r"-cp(\d+)", og_filename)
        if match:
            return match.group(1)
        else:
            return "NoArch"


def fetch_projects():
    """
    Step 1: Fetch all projects
    """
    response = requests.get(BASE_URL, headers=HEADERS, data=PAYLOAD)
    response.raise_for_status()
    return response.json()["result"]["projects"]


def fetch_project_versions(project_name):
    """
    Step 2: Fetch project details
    """
    url = f"{BASE_URL}{project_name}"
    response = requests.get(url, headers=HEADERS, data=PAYLOAD)
    response.raise_for_status()
    return response.json()["result"]


def main():
    # Create Excel workbook
    wb = Workbook()
    ws = wb.active
    ws.title = "ppc64le_packages"

    # Header
    ws.append([
        "package_name",
        "package_version",
        "wheel_name",
        "python_version",
        "download_url"
    ])

    projects = fetch_projects()

    for project in projects:
        print(f"Processing project: {project}")
        versions = fetch_project_versions(project)

        for version, version_data in versions.items():
            package_name = version_data.get("name", project)
            package_version = version_data.get("version", version)

            links = version_data.get("+links", [])
            for link in links:
                if link.get("rel") != "releasefile":
                    continue

                href = link.get("href")
                hash_spec = link.get("hash_spec")

                wheel_name = href.split("/")[-1]
                python_version = get_python_version_from_wheel(wheel_name)
                download_url = f"{href}#{hash_spec}"

                ws.append([
                    package_name,
                    package_version,
                    wheel_name,
                    python_version,
                    download_url
                ])

    # Save Excel file
    output_file = "packages_ppc64le.xlsx"
    wb.save(output_file)
    print(f"\n✅ Excel file generated: {output_file}")


if __name__ == "__main__":
    main()
