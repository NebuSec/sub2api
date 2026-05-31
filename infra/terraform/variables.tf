variable "aws_region" {
  description = "AWS region for the Sub2API deployment."
  type        = string
  default     = "us-west-1"
}

variable "project_name" {
  description = "Project name prefix shared with Vega infrastructure."
  type        = string
  default     = "vega"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "prod"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "security"
}

variable "cost_center" {
  description = "CostCenter tag value."
  type        = string
  default     = "vega"
}

variable "vega_state_bucket" {
  description = "S3 bucket containing the shared Vega Terraform state."
  type        = string
  default     = "vega-terraform-state-prod-us-west-1"
}

variable "vega_state_key" {
  description = "S3 key containing the shared Vega Terraform state."
  type        = string
  default     = "vega/prod/terraform.tfstate"
}

variable "vega_state_region" {
  description = "AWS region for the shared Vega Terraform state bucket."
  type        = string
  default     = "us-west-1"
}

variable "sub2api_image_tag" {
  description = "Immutable pinned Sub2API image tag mirrored into the shared ECR repository."
  type        = string
  default     = "replace-with-sub2api-version-sha"

  validation {
    condition     = var.sub2api_image_tag != "latest" && var.sub2api_image_tag != "dev-current" && var.sub2api_image_tag != "prod-current"
    error_message = "Prod must use an immutable pinned Sub2API image tag, not latest or mutable current tags."
  }
}

variable "sub2api_desired_count" {
  description = "Desired task count for the prod Sub2API service."
  type        = number
  default     = 2
}

variable "sub2api_cpu" {
  description = "Fargate CPU units for the prod Sub2API service."
  type        = number
  default     = 512
}

variable "sub2api_memory" {
  description = "Fargate memory in MiB for the prod Sub2API service."
  type        = number
  default     = 1024
}

variable "sub2api_run_mode" {
  description = "Sub2API run mode for prod."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "simple"], var.sub2api_run_mode)
    error_message = "sub2api_run_mode must be standard or simple."
  }
}

variable "sub2api_admin_email" {
  description = "Bootstrap admin email for prod Sub2API."
  type        = string
  default     = "admin@sub2api.local"
}

variable "sub2api_database_instance_class" {
  description = "Prod Sub2API RDS instance class."
  type        = string
  default     = "db.t4g.small"
}

variable "sub2api_database_allocated_storage" {
  description = "Prod Sub2API RDS allocated storage in GiB."
  type        = number
  default     = 50
}

variable "sub2api_database_multi_az" {
  description = "Whether prod Sub2API RDS uses Multi-AZ."
  type        = bool
  default     = false
}

variable "sub2api_database_backup_retention_period" {
  description = "Prod Sub2API RDS backup retention in days."
  type        = number
  default     = 14
}

variable "sub2api_database_deletion_protection" {
  description = "Whether prod Sub2API RDS deletion protection is enabled."
  type        = bool
  default     = true
}

variable "sub2api_database_skip_final_snapshot" {
  description = "Whether prod Sub2API RDS skips final snapshot on destroy."
  type        = bool
  default     = false
}

variable "sub2api_database_apply_immediately" {
  description = "Whether prod Sub2API RDS changes apply immediately."
  type        = bool
  default     = false
}

variable "sub2api_redis_node_type" {
  description = "Prod Sub2API Redis node type."
  type        = string
  default     = "cache.t4g.micro"
}

variable "sub2api_redis_num_cache_clusters" {
  description = "Number of prod Sub2API Redis cache nodes."
  type        = number
  default     = 1
}

variable "sub2api_allowed_upstream_hosts" {
  description = "Allowed upstream hosts Sub2API may proxy to in prod."
  type        = list(string)
  default = [
    "api.openai.com",
    "api.anthropic.com",
    "generativelanguage.googleapis.com",
    "cloudcode-pa.googleapis.com",
  ]
}

variable "cloudflared_image" {
  description = "Pinned cloudflared image used for the prod Sub2API admin tunnel."
  type        = string
  default     = "cloudflare/cloudflared:2026.5.0-amd64"
}

variable "cloudflared_desired_count" {
  description = "Desired task count for the prod Cloudflare Tunnel connector."
  type        = number
  default     = 1
}

variable "cloudflared_cpu" {
  description = "Fargate CPU units for the prod Cloudflare Tunnel connector."
  type        = number
  default     = 256
}

variable "cloudflared_memory" {
  description = "Fargate memory in MiB for the prod Cloudflare Tunnel connector."
  type        = number
  default     = 512
}

variable "cloudflare_sub2api_tunnel_token_secret_name" {
  description = "Existing Secrets Manager secret containing the Cloudflare Tunnel token for prod Sub2API admin access."
  type        = string
  default     = "vega-prod/cloudflare-sub2api-tunnel-token"
}

variable "log_retention_in_days" {
  description = "CloudWatch log retention for the Cloudflare Tunnel connector."
  type        = number
  default     = 30
}
