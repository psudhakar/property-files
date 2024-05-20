provider "aws" {
  region = "us-gov-west-1"
  profile = "govcloud"
}

terraform {
	required_providers {
		aws = {
	    version = "~> 5.40.0"
		}
  }
}
