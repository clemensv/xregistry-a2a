import os
import json
from pathlib import Path
import pandas as pd
import subprocess

# Base directory to search
script_dir = Path(os.path.dirname(os.path.abspath(__file__)))
root_dir = script_dir.parent

# Load model.json to drive the script
model_file = root_dir / "xreg" / "model.json"
with open(model_file, "r", encoding="utf-8") as f:
    model = json.load(f)

# Define the output directory for index files
output_dir = script_dir

# Iterate over all groups in the model
for group_key, group_data in model["groups"].items():
    group_plural = group_data.get("plural", group_key)
    group_singular = group_data.get("singular", group_key[:-1])

    # Iterate over resources within the group
    for resource_key, resource_data in group_data.get("resources", {}).items():
        resource_plural = resource_data.get("plural", resource_key)
        resource_singular = resource_data.get("singular", resource_key[:-1])

        # Update base directory to use model-driven group_plural
        base_dir = Path(os.path.join(root_dir, "registry", group_plural))
        if not base_dir.exists():
            print(f"Directory {base_dir} does not exist. Skipping.")
            continue

        # Initialize a dynamic index for the current resource
        current_resource_index = []

        # Traverse directory structure using model-driven resource_plural
        for provider_dir in base_dir.iterdir():
            if provider_dir.is_dir():
                if not (provider_dir / resource_plural).is_dir():
                    continue
                for resource_dir in (provider_dir / resource_plural).iterdir():
                    index_file = resource_dir / "index.json"
                    if index_file.exists():
                        with open(index_file, 'r', encoding='utf-8') as f:
                            try:
                                resource_data = json.load(f)
                            except json.JSONDecodeError:
                                continue

                            provider_id = provider_dir.name
                            resource_id = resource_dir.name

                            # Index resource
                            current_resource_index.append({
                                "id": f"{provider_id}/{resource_id}",
                                "xid": f"{provider_id}/{resource_id}",
                                "provider": provider_id,
                                "resource": resource_id,
                                "name": resource_data.get("name"),
                                "description": resource_data.get("description"),
                            })
                            
        # Write the dynamic index for the current resource to a file
        output_file = output_dir / f"{resource_plural}_index.json"
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(current_resource_index, f, ensure_ascii=False, indent=4)

# Define the directory containing the package.json for flex-indexer
flex_indexer_dir = Path(script_dir) / "flex-indexer"

# Run npm install to install dependencies
subprocess.run(["npm", "install"], cwd=flex_indexer_dir, check=True)

# Run the npm script for flex-indexer
subprocess.run(["npm", "start"], cwd=flex_indexer_dir, check=True)
