terraform {
  backend "http" {
    # See backend.env for configuration of the following fields:
    # address
    # lock_address
    # unlock_address
    # password

    # Do not change the following
    username = "cos"
    update_method          = "POST"
    lock_method            = "PUT"
    unlock_method          = "DELETE"
    skip_cert_verification = "false"
  }
}
