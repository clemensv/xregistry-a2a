#!/bin/bash

SCRIPT_DIR=$(dirname "$(readlink -f "$PWD$0")")
REPO_ROOT=$(readlink -f "$SCRIPT_DIR/..")
OPENAPI_EXPORT_DIR="$REPO_ROOT/openapi/openapi.json"

if [ ! -d "$REPO_ROOT/xreg/.xregistry-spec" ]; then
    git clone https://github.com/xregistry/spec.git "$REPO_ROOT/xreg/.xregistry-spec"
fi

SCHEMA_GENERATOR="$REPO_ROOT/xreg/.xregistry-spec/tools/schema-generator.py"
python $SCHEMA_GENERATOR \
    --type openapi \
    --output "$OPENAPI_EXPORT_DIR" \
    $SCRIPT_DIR/model.json

python $SCHEMA_GENERATOR \
    --type json-schema \
    --output "$SCRIPT_DIR/json-schema.json" \
    $SCRIPT_DIR/model.json