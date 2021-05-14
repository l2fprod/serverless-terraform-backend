variable "ibmcloud_api_key" {
  type = string
}

variable "ibmcloud_timeout" {
  type    = number
  default = 600
}

variable "region" {
  type    = string
  default = "us-south"
}

variable "basename" {
  type    = string
  default = "serverless-terraform-backend"
}

variable "resource_group" {
  type    = string
  default = ""
}

variable "tags" {
  type    = list(string)
  default = ["terraform", "tutorial"]
}

terraform {
  required_version = ">=0.13"
  required_providers {
    ibm = {
      source = "IBM-Cloud/ibm"
    }
  }
}

provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.region
  ibmcloud_timeout = var.ibmcloud_timeout
}

# a new or existing resource group to create resources
resource "ibm_resource_group" "group" {
  count = var.resource_group != "" ? 0 : 1
  name  = "${var.basename}-group"
  tags  = var.tags
}

data "ibm_resource_group" "group" {
  count = var.resource_group != "" ? 1 : 0
  name  = var.resource_group
}

locals {
  resource_group_id = var.resource_group != "" ? data.ibm_resource_group.group.0.id : ibm_resource_group.group.0.id
}

# a COS instance
resource "ibm_resource_instance" "cos" {
  name              = "${var.basename}-cos"
  resource_group_id = local.resource_group_id
  service           = "cloud-object-storage"
  plan              = "standard"
  location          = "global"
  tags              = concat(var.tags, ["service"])
}

resource "ibm_resource_key" "cos_key" {
  name                 = "${var.basename}-cos-key"
  resource_instance_id = ibm_resource_instance.cos.id
  role                 = "Writer"
}

# a bucket
resource "ibm_cos_bucket" "bucket" {
  bucket_name          = "${var.basename}-bucket"
  resource_instance_id = ibm_resource_instance.cos.id
  region_location      = var.region
  storage_class        = "smart"
}

# a namespace for the backend functions
resource "ibm_function_namespace" "namespace" {
  name              = "${var.basename}-namespace"
  resource_group_id = local.resource_group_id
}

# a package to group the functions
resource "ibm_function_package" "package" {
  name = "${var.basename}-package"
  namespace = ibm_function_namespace.namespace.name
  user_defined_parameters = <<EOF
    [
      {
        "key": "services.storage.apiEndpoint",
        "value": "${ibm_cos_bucket.bucket.s3_endpoint_private}"
      },
      {
        "key": "services.storage.instanceId",
        "value": "${ibm_resource_instance.cos.resource_id}"
      },
      {
        "key": "services.storage.bucket",
        "value": "${ibm_cos_bucket.bucket.bucket_name}"
      }
    ]
EOF
}

# the backend implementation
resource "ibm_function_action" "backend" {
  name = "${ibm_function_package.package.name}/backend"
  namespace = ibm_function_namespace.namespace.name
  exec {
    kind = "nodejs:10"
    code = file("backend.js")
  }
  publish = true
  user_defined_annotations = <<EOF
    [
      {
        "key": "web-export",
        "value": true
      },
      {
        "key": "raw-http",
        "value": true
      },
      {
        "key": "final",
        "value": true
      }
    ]
EOF
}

resource "local_file" "backend-config" {
  content = <<EOF
# TF_HTTP_ADDRESS points to the Cloud Functions action implementing the backend.
# It is reused for locking implementation too.
#
# env: name for the terraform state, e.g mystate, us/south/staging (.tfstate will be added automatically)
# versioning: set to true to keep multiple copies of the states in the storage
export TF_HTTP_ADDRESS="${ibm_function_action.backend.target_endpoint_url}?env=dev&versioning=true"
export TF_HTTP_PASSWORD=${ibm_resource_key.cos_key.credentials.apikey}

# comment the following variables to disable locking
export TF_HTTP_LOCK_ADDRESS=$TF_HTTP_ADDRESS
export TF_HTTP_UNLOCK_ADDRESS=$TF_HTTP_ADDRESS
EOF
  filename = "../020-use-backend/backend.env"
}
