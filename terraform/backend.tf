terraform {
  backend "http" {
    # Serverless backend endpoint
    # Optional query parameters:
    # env: name for the terraform state, e.g mystate, us/south/staging (.tfstate will be added automatically)
    # versioning: set to true to keep multiple copies of the states in the storage
    address = "https://API_GATEWAY_URL?env=name&versioning=true"

    # Uncomment to enable locking. Set to same value as address
    # lock_address = "https://API_GATEWAY_URL?env=name&versioning=true"
    # unlock_address = "https://API_GATEWAY_URL?env=name&versioning=true"

    # API Key for Cloud Object Storage
    password = "SET_YOUR_KEY"

    # Do not change the following
    username = "cos"
    update_method          = "POST"
    lock_method            = "PUT"
    unlock_method          = "DELETE"
    skip_cert_verification = "false"
  }
}
