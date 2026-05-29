provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "terraform_remote_state" "vega" {
  backend = "s3"

  config = {
    bucket = var.vega_state_bucket
    key    = var.vega_state_key
    region = var.vega_state_region
  }
}

data "aws_secretsmanager_secret" "sub2api_db_credentials" {
  name = data.terraform_remote_state.vega.outputs.secret_names["sub2api_db_credentials"]
}

data "aws_secretsmanager_secret" "sub2api_redis_auth" {
  name = data.terraform_remote_state.vega.outputs.secret_names["sub2api_redis_auth"]
}

data "aws_secretsmanager_secret" "sub2api_runtime_secret" {
  name = data.terraform_remote_state.vega.outputs.secret_names["sub2api_runtime_secret"]
}

data "aws_secretsmanager_secret" "sub2api_admin_secret" {
  name = data.terraform_remote_state.vega.outputs.secret_names["sub2api_admin_secret"]
}

data "aws_secretsmanager_secret" "cloudflare_sub2api_tunnel_token" {
  name = var.cloudflare_sub2api_tunnel_token_secret_name
}

data "aws_vpc" "shared" {
  id = data.terraform_remote_state.vega.outputs.vpc_id
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
    CostCenter  = var.cost_center
  }

  security_group_ids       = data.terraform_remote_state.vega.outputs.security_group_ids
  task_role_arns           = data.terraform_remote_state.vega.outputs.task_role_arns
  cloudwatch_log_groups    = data.terraform_remote_state.vega.outputs.cloudwatch_log_group_names
  ecr_repository_urls      = data.terraform_remote_state.vega.outputs.ecr_repository_urls
  ecs_cluster_name         = data.terraform_remote_state.vega.outputs.ecs_cluster_name
  public_subnet_ids        = data.terraform_remote_state.vega.outputs.public_subnet_ids
  private_subnet_ids       = data.terraform_remote_state.vega.outputs.private_subnet_id_list
  sub2api_service_name     = "vega-sub2api"
  cloudflared_service_name = "vega-cloudflared-sub2api"
}

module "sub2api_service" {
  source = "./modules/sub2api_service"

  name_prefix      = local.name_prefix
  environment      = var.environment
  cluster_id       = local.ecs_cluster_name
  cluster_name     = local.ecs_cluster_name
  vpc_id           = data.terraform_remote_state.vega.outputs.vpc_id
  subnet_ids       = local.private_subnet_ids
  sub2api_image    = "${local.ecr_repository_urls[local.sub2api_service_name]}:${var.sub2api_image_tag}"
  log_group_name   = local.cloudwatch_log_groups[local.sub2api_service_name]
  desired_count    = var.sub2api_desired_count
  cpu              = var.sub2api_cpu
  memory           = var.sub2api_memory
  assign_public_ip = false
  run_mode         = var.sub2api_run_mode
  admin_email      = var.sub2api_admin_email

  allowed_client_security_group_ids = {
    cloudflared = aws_security_group.cloudflared.id
    api         = local.security_group_ids.api
    llm_proxy   = local.security_group_ids.llm_proxy
  }

  task_execution_role_arn         = data.terraform_remote_state.vega.outputs.task_execution_role_arn
  task_role_arn                   = local.task_role_arns[local.sub2api_service_name]
  database_credentials_secret_arn = data.aws_secretsmanager_secret.sub2api_db_credentials.arn
  redis_auth_secret_arn           = data.aws_secretsmanager_secret.sub2api_redis_auth.arn
  runtime_secret_arn              = data.aws_secretsmanager_secret.sub2api_runtime_secret.arn
  admin_secret_arn                = data.aws_secretsmanager_secret.sub2api_admin_secret.arn

  database_instance_class          = var.sub2api_database_instance_class
  database_allocated_storage       = var.sub2api_database_allocated_storage
  database_multi_az                = var.sub2api_database_multi_az
  database_backup_retention_period = var.sub2api_database_backup_retention_period
  database_deletion_protection     = var.sub2api_database_deletion_protection
  database_skip_final_snapshot     = var.sub2api_database_skip_final_snapshot
  database_apply_immediately       = var.sub2api_database_apply_immediately
  redis_node_type                  = var.sub2api_redis_node_type
  redis_num_cache_clusters         = var.sub2api_redis_num_cache_clusters
  allowed_upstream_hosts           = var.sub2api_allowed_upstream_hosts
  tags                             = local.common_tags
}

resource "aws_cloudwatch_log_group" "cloudflared" {
  name              = "/vega/${var.environment}/${local.cloudflared_service_name}"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.common_tags, {
    Component = "cloudflared-sub2api"
    Name      = "/vega/${var.environment}/${local.cloudflared_service_name}"
    Service   = local.cloudflared_service_name
  })
}

resource "aws_security_group" "cloudflared" {
  name        = "${local.name_prefix}-cloudflared-sub2api"
  description = "Cloudflare Tunnel connector access to prod Sub2API admin UI"
  vpc_id      = data.terraform_remote_state.vega.outputs.vpc_id

  tags = merge(local.common_tags, {
    Component = "cloudflared-sub2api"
    Name      = "${local.name_prefix}-cloudflared-sub2api"
    Role      = "cloudflared-sub2api"
  })
}

resource "aws_vpc_security_group_egress_rule" "cloudflared_to_cloudflare" {
  security_group_id = aws_security_group.cloudflared.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
  description       = "Outbound HTTPS to Cloudflare Tunnel edge"
}

resource "aws_vpc_security_group_egress_rule" "cloudflared_to_cloudflare_tunnel" {
  security_group_id = aws_security_group.cloudflared.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 7844
  ip_protocol       = "tcp"
  to_port           = 7844
  description       = "Outbound HTTP/2 tunnel traffic to Cloudflare edge"
}

resource "aws_vpc_security_group_egress_rule" "cloudflared_to_sub2api" {
  security_group_id            = aws_security_group.cloudflared.id
  referenced_security_group_id = module.sub2api_service.security_group_id
  from_port                    = 8080
  ip_protocol                  = "tcp"
  to_port                      = 8080
  description                  = "Cloudflare Tunnel connector to Sub2API admin UI"
}

resource "aws_vpc_security_group_egress_rule" "cloudflared_dns_tcp" {
  security_group_id = aws_security_group.cloudflared.id
  cidr_ipv4         = data.aws_vpc.shared.cidr_block
  from_port         = 53
  ip_protocol       = "tcp"
  to_port           = 53
  description       = "Cloudflare Tunnel connector TCP DNS egress inside the VPC"
}

resource "aws_vpc_security_group_egress_rule" "cloudflared_dns_udp" {
  security_group_id = aws_security_group.cloudflared.id
  cidr_ipv4         = data.aws_vpc.shared.cidr_block
  from_port         = 53
  ip_protocol       = "udp"
  to_port           = 53
  description       = "Cloudflare Tunnel connector UDP DNS egress inside the VPC"
}

resource "aws_ecs_task_definition" "cloudflared_sub2api" {
  family                   = "${local.name_prefix}-cloudflared-sub2api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cloudflared_cpu
  memory                   = var.cloudflared_memory
  execution_role_arn       = data.terraform_remote_state.vega.outputs.task_execution_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "cloudflared"
      image     = var.cloudflared_image
      essential = true
      command   = ["tunnel", "--protocol", "http2", "--no-autoupdate", "run"]
      secrets = [
        {
          name      = "TUNNEL_TOKEN"
          valueFrom = data.aws_secretsmanager_secret.cloudflare_sub2api_tunnel_token.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.cloudflared.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "cloudflared"
        }
      }
    }
  ])

  tags = merge(local.common_tags, {
    Component = "cloudflared-sub2api"
    Name      = "${local.name_prefix}-cloudflared-sub2api"
    Service   = local.cloudflared_service_name
  })
}

resource "aws_ecs_service" "cloudflared_sub2api" {
  name            = "${local.name_prefix}-cloudflared-sub2api"
  cluster         = local.ecs_cluster_name
  task_definition = aws_ecs_task_definition.cloudflared_sub2api.arn
  desired_count   = var.cloudflared_desired_count
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = local.public_subnet_ids
    security_groups  = [aws_security_group.cloudflared.id]
    assign_public_ip = true
  }

  service_connect_configuration {
    enabled   = true
    namespace = module.sub2api_service.service_connect_namespace_arn
  }

  tags = merge(local.common_tags, {
    Component = "cloudflared-sub2api"
    Name      = "${local.name_prefix}-cloudflared-sub2api"
    Service   = local.cloudflared_service_name
  })

  depends_on = [
    module.sub2api_service,
    aws_cloudwatch_log_group.cloudflared,
  ]
}
