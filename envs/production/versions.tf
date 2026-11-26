terraform {
  required_version = ">= 1.11" # write-only arguments

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # ECS native blue/green (deployment_configuration.strategy and
      # load_balancer.advanced_configuration) needs a recent 6.x provider.
      # Confirm the minimum version in the provider changelog.
      version = "~> 6.4"
    }
    random = {
      source = "hashicorp/random"
      # Ephemeral random_password, used to generate APP_KEY outside state.
      version = "~> 3.7"
    }
  }

  # Bucket is created by bootstrap/. S3-native locking replaces the
  # DynamoDB lock table.
  backend "s3" {
    bucket       = "raventrack-billing-dashboard-tfstate"
    key          = "production/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
