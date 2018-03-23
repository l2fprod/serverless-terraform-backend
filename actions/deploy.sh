#!/bin/bash
# load configuration variables
PACKAGE_NAME=terraform
source local.env

function usage() {
  echo "Usage: $0 [--install,--uninstall,--update,--installApi,--uninstallApi,--env,--createCOS]"
}

function createCOS() {
  bx service create cloud-object-storage Lite serverless-terraform-storage
  bx service key-create serverless-terraform-storage for-cli
  bx service key-show serverless-terraform-storage for-cli
}

function install() {
  echo "Creating $PACKAGE_NAME package"
  bx wsk package create $PACKAGE_NAME \
    -p services.storage.apiEndpoint "$STORAGE_API_ENDPOINT"\
    -p services.storage.instanceId "$STORAGE_RESOURCE_INSTANCE_ID"\
    -p services.storage.bucket "$STORAGE_BUCKET_STATES"

  echo "Creating actions"
  bx wsk action create $PACKAGE_NAME/backend\
    backend.js \
    --web raw --annotation final true --kind nodejs:8
}

function uninstall() {
  echo "Removing actions..."
  bx wsk action delete $PACKAGE_NAME/backend

  echo "Removing package..."
  bx wsk package delete $PACKAGE_NAME

  echo "Done"
  bx wsk list
}

function update() {
  echo "Updating actions..."
  bx wsk action update $PACKAGE_NAME/backend    backend.js  --kind nodejs:8
}

function showenv() {
  echo "PACKAGE_NAME=$PACKAGE_NAME"
}

function installApi() {
  bx wsk api create /terraform/1 /backend GET    $PACKAGE_NAME/backend --response-type http
  bx wsk api create /terraform/1 /backend POST   $PACKAGE_NAME/backend --response-type http
  bx wsk api create /terraform/1 /backend PUT    $PACKAGE_NAME/backend --response-type http
  bx wsk api create /terraform/1 /backend DELETE $PACKAGE_NAME/backend --response-type http
}

function uninstallApi() {
  bx wsk api delete /terraform/1
}

function recycle() {
  uninstallApi
  uninstall
  install
  installApi
}

case "$1" in
"--install" )
install
;;
"--uninstall" )
uninstall
;;
"--update" )
update
;;
"--env" )
showenv
;;
"--installApi" )
installApi
;;
"--uninstallApi" )
uninstallApi
;;
"--recycle" )
recycle
;;
"--createCOS" )
createCOS
;;
* )
usage
;;
esac
