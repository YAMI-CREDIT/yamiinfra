terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "yamicredit"

    workspaces {
      name = "yamiinfra"
    }
  }
}