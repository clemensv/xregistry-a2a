#!/bin/bash
# run on Linux

CONTAINER_NAME="xregistry-server"
ARCHIVE_PATH="/tmp/xr_live_data.tar.gz"

# Determine repository root directory
SCRIPT_DIR=$(dirname "$(readlink -f "$PWD$0")")
REPO_ROOT=$(readlink -f "$SCRIPT_DIR/..")
DATA_EXPORT_DIR="$REPO_ROOT/site/public/registry"
SITE_DIR="$REPO_ROOT/site"

echo "Repository root directory: $REPO_ROOT"
echo "Data export directory: $DATA_EXPORT_DIR"
echo "Container name: $CONTAINER_NAME"
echo "Archive path: $ARCHIVE_PATH"


# check out https://github.com/clemensv/xregistry-viewer into $SITE_DIR
if [ ! -d "$SITE_DIR" ]; then
  git clone https://github.com/clemensv/xregistry-viewer "$SITE_DIR"
else
  cd "$SITE_DIR"
  git pull
  cd "$REPO_ROOT"
fi

# Start or reuse the xregistry server container
if [ "$(docker ps -q -f name="${CONTAINER_NAME}")" ]; then
  echo "Container ${CONTAINER_NAME} is already running."
  exit
else
  CONTAINER_ID=$(docker run -d --name "${CONTAINER_NAME}" -v $REPO_ROOT:/workspace -p 8080:8080 ghcr.io/xregistry/xrserver-all --recreatedb)
fi

# Wait for the server to be ready
echo "Waiting for xregistry server to be ready..."
until curl --silent --get http://localhost:8080 -i | grep "200 OK" > /dev/null; do
  sleep 5
done

# Update the model
echo "Updating model..."
docker exec "${CONTAINER_ID}" /bin/bash ls -l /workspace
docker exec "${CONTAINER_ID}" /xr model update /workspace/xreg/model.json -s localhost:8080

# Create entries for each registry index.json
echo "Creating registry entries..."
docker exec "${CONTAINER_ID}" /bin/sh -c '
 REGISTRY_DIR=/workspace/registry
 find $REGISTRY_DIR -type f -name index.json | while read file; do
   path=${file#"$REGISTRY_DIR"/}
   path=${path%/index.json}
   /xr create "$path" -d "@$file" -s localhost:8080
   if [ $? -ne 0 ]; then
     echo "Error processing file: $file"
   else
     echo "Processed file: $file"
   fi 
 done
'

# Export the live data as a tarball
echo "Exporting live data to $ARCHIVE_PATH..."
docker exec "${CONTAINER_ID}" /bin/sh -c "
  mkdir -p /tmp/live
  /xr download -s localhost:8080 /tmp/live -u https://mcpxreg.org/
  cd /tmp/live
  tar czf $ARCHIVE_PATH .
"

# Copy the archive to the host
echo "Copying archive to $DATA_EXPORT_DIR..."
mkdir -p "$DATA_EXPORT_DIR"
docker cp "${CONTAINER_ID}:$ARCHIVE_PATH" "$DATA_EXPORT_DIR/xr_live_data.tar.gz"
tar xzf "$DATA_EXPORT_DIR/xr_live_data.tar.gz" -C "$DATA_EXPORT_DIR"
rm "$DATA_EXPORT_DIR/xr_live_data.tar.gz"

# Stop and remove the container
echo "Stopping and removing xregistry server..."
docker stop "${CONTAINER_ID}"
docker rm "${CONTAINER_ID}"
echo "xregistry server stopped and removed."

# Build the index
echo "Building index..."
yes | pip install pandas --quiet
python "$REPO_ROOT/index/build_index.py"

# Copy additional files
echo "Copying flex.json files to $REPO_ROOT/site/public/registry/..."
cp $REPO_ROOT/index/flex/*.flex.json $DATA_EXPORT_DIR
cp $REPO_ROOT/xreg/registry-staticwebapp.config.json $DATA_EXPORT_DIR/staticwebapp.config.json

# Build the Angular app
echo "Building the Angular app..."
BUILD_OUTPUT="dist/xregistry-viewer"
cd "$SITE_DIR"
if [ -f "package.json" ]; then
  npm install 
  npm run build -- --config production --output-path $BUILD_OUTPUT
fi

# Stage the build output into the 'gh-pages' branch
echo "Staging build output into 'gh-pages' branch..."




# Save the current branch name (default to main if not found)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")

TMP_DIR=$(mktemp -d)
echo "Cloning repository into temporary directory: $TMP_DIR"
branch="gh-pages"
if git ls-remote --exit-code --heads "$REPO_ROOT" "$branch" &> /dev/null; then
    git clone "$REPO_ROOT" "$TMP_DIR" -b "$branch" > /dev/null
else
    echo "Branch $branch does not exist. Cloning default branch instead."
    git clone "$REPO_ROOT" "$TMP_DIR" > /dev/null
fi

cd "$TMP_DIR"

# Create an orphan gh-pages branch (or reset it if it already exists)
if git show-ref --quiet refs/heads/gh-pages; then
  git checkout gh-pages
  git rm -rf . > /dev/null 2>&1 || true
else
  git checkout --orphan gh-pages
  git reset --hard
fi

# Clean the branch and copy in the build output from the main repo
find "$TMP_DIR" -mindepth 1 -maxdepth 1 ! -name ".git" -exec rm -rf {} +
cp -r $DATA_EXPORT_DIR/$BUILD_OUTPUT/* .

touch .nojekyll

git add .
git commit -m "Deploy Angular app to gh-pages" || echo "Nothing to commit"

echo "Build output staged in gh-pages branch in temporary dir: $TMP_DIR"
echo "Please push the 'gh-pages' branch from this directory to deploy on GitHub Pages."

# Switch back to the original branch
git push origin gh-pages
cd "$REPO_ROOT"
git checkout "$CURRENT_BRANCH"

echo "Process complete."
