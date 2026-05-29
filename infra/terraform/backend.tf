terraform {
  backend "s3" {
    bucket         = "vega-terraform-state-prod-us-west-1"
    key            = "sub2api/prod/terraform.tfstate"
    region         = "us-west-1"
    dynamodb_table = "vega-terraform-locks-prod"
    encrypt        = true
  }
}
