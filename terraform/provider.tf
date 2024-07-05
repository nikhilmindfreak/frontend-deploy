terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.48.0"
    }
  }
  backend "s3" {
    bucket = "devopsme-remote-state"
    key    = "expense-dev-frontend"  # always change key name for every new resource
    region = "us-east-1"
    dynamodb_table = "devopsme-locking"
  }
}

#provide authentication here
provider "aws" {
  region = "us-east-1"
}