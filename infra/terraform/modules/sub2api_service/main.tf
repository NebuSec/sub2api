variable "name_prefix" {
  description = "Prefix used for Sub2API resources."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "cluster_id" {
  description = "ECS cluster ID or ARN."
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name for CloudWatch metric dimensions."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for Sub2API resources."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for Sub2API tasks and data stores."
  type        = list(string)
}

variable "allowed_client_security_group_ids" {
  description = "Security groups allowed to call Sub2API."
  type        = map(string)
}

variable "task_execution_role_arn" {
  description = "ECS task execution role ARN."
  type        = string
}

variable "task_role_arn" {
  description = "Sub2API ECS task role ARN."
  type        = string
}

variable "sub2api_image" {
  description = "Fully-qualified Sub2API container image URI."
  type        = string
}

variable "database_credentials_secret_arn" {
  description = "Secrets Manager ARN for generated Sub2API database credentials."
  type        = string
}

variable "redis_auth_secret_arn" {
  description = "Secrets Manager ARN for generated Sub2API Redis auth token."
  type        = string
}

variable "runtime_secret_arn" {
  description = "Secrets Manager ARN for generated Sub2API JWT/TOTP secrets."
  type        = string
}

variable "admin_secret_arn" {
  description = "Secrets Manager ARN for generated Sub2API bootstrap admin credentials."
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group for Sub2API logs."
  type        = string
}

variable "desired_count" {
  description = "Desired Sub2API task count."
  type        = number
  default     = 1
}

variable "cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 1024
}

variable "assign_public_ip" {
  description = "Whether Sub2API tasks get a public IP."
  type        = bool
  default     = false
}

variable "container_port" {
  description = "Sub2API container port."
  type        = number
  default     = 8080
}

variable "cpu_architecture" {
  description = "CPU architecture for the Sub2API task runtime platform."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "run_mode" {
  description = "Sub2API run mode."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "simple"], var.run_mode)
    error_message = "run_mode must be standard or simple."
  }
}

variable "admin_email" {
  description = "Bootstrap Sub2API admin email."
  type        = string
  default     = "admin@sub2api.local"
}

variable "database_instance_class" {
  description = "RDS instance class for Sub2API Postgres."
  type        = string
  default     = "db.t4g.micro"
}

variable "database_allocated_storage" {
  description = "RDS allocated storage in GiB for Sub2API Postgres."
  type        = number
  default     = 20
}

variable "database_multi_az" {
  description = "Whether Sub2API Postgres uses Multi-AZ."
  type        = bool
  default     = false
}

variable "database_backup_retention_period" {
  description = "Sub2API Postgres backup retention in days."
  type        = number
  default     = 1
}

variable "database_deletion_protection" {
  description = "Whether Sub2API Postgres deletion protection is enabled."
  type        = bool
  default     = false
}

variable "database_skip_final_snapshot" {
  description = "Whether Sub2API Postgres skips final snapshot on destroy."
  type        = bool
  default     = true
}

variable "database_apply_immediately" {
  description = "Whether Sub2API Postgres changes apply immediately."
  type        = bool
  default     = true
}

variable "redis_node_type" {
  description = "ElastiCache node type for Sub2API Redis."
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_num_cache_clusters" {
  description = "Number of cache nodes in the Sub2API Redis replication group."
  type        = number
  default     = 1
}

variable "allowed_upstream_hosts" {
  description = "Sub2API URL allowlist upstream hosts."
  type        = list(string)
  default = [
    "api.openai.com",
    "api.anthropic.com",
    "generativelanguage.googleapis.com",
    "cloudcode-pa.googleapis.com",
  ]
}

variable "tags" {
  description = "Tags applied to Sub2API resources."
  type        = map(string)
  default     = {}
}

data "aws_region" "current" {}

locals {
  service_name   = "vega-sub2api"
  database_name  = "sub2api"
  database_user  = "sub2api"
  redis_port     = 6379
  namespace_name = "${var.name_prefix}-svc"
  tags           = merge(var.tags, { Component = "sub2api-service" })
}

resource "random_password" "database" {
  length  = 32
  special = false
}

resource "random_password" "redis" {
  length  = 32
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 32
  special = false
}

resource "random_id" "totp_encryption_key" {
  byte_length = 32
}

resource "random_password" "admin" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = var.database_credentials_secret_arn
  secret_string = jsonencode({
    host         = aws_db_instance.sub2api.address
    port         = aws_db_instance.sub2api.port
    dbname       = local.database_name
    username     = local.database_user
    password     = random_password.database.result
    database_url = "postgresql://${local.database_user}:${urlencode(random_password.database.result)}@${aws_db_instance.sub2api.address}:${aws_db_instance.sub2api.port}/${local.database_name}?sslmode=require"
  })
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = var.redis_auth_secret_arn
  secret_string = jsonencode({
    host       = aws_elasticache_replication_group.redis.primary_endpoint_address
    port       = local.redis_port
    auth_token = random_password.redis.result
    tls        = true
  })
}

resource "aws_secretsmanager_secret_version" "runtime" {
  secret_id = var.runtime_secret_arn
  secret_string = jsonencode({
    jwt_secret          = random_password.jwt_secret.result
    totp_encryption_key = random_id.totp_encryption_key.hex
  })
}

resource "aws_secretsmanager_secret_version" "admin" {
  secret_id = var.admin_secret_arn
  secret_string = jsonencode({
    email    = var.admin_email
    password = random_password.admin.result
  })
}

resource "aws_security_group" "sub2api" {
  name        = "${var.name_prefix}-sub2api"
  description = "Sub2API task access"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-sub2api"
    Role = "sub2api"
  })
}

resource "aws_security_group" "database" {
  name        = "${var.name_prefix}-sub2api-postgres"
  description = "Postgres access for Sub2API"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-sub2api-postgres"
    Role = "sub2api-postgres"
  })
}

resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-sub2api-redis"
  description = "Redis access for Sub2API"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-sub2api-redis"
    Role = "sub2api-redis"
  })
}

resource "aws_vpc_security_group_ingress_rule" "sub2api_from_clients" {
  for_each = var.allowed_client_security_group_ids

  security_group_id            = aws_security_group.sub2api.id
  referenced_security_group_id = each.value
  from_port                    = var.container_port
  ip_protocol                  = "tcp"
  to_port                      = var.container_port
  description                  = "Sub2API traffic from ${each.key}"
}

resource "aws_vpc_security_group_ingress_rule" "database_from_sub2api" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.sub2api.id
  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
  description                  = "Postgres access from Sub2API"
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_sub2api" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = aws_security_group.sub2api.id
  from_port                    = local.redis_port
  ip_protocol                  = "tcp"
  to_port                      = local.redis_port
  description                  = "Redis access from Sub2API"
}

resource "aws_vpc_security_group_egress_rule" "sub2api" {
  security_group_id = aws_security_group.sub2api.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow Sub2API outbound traffic"
}

resource "aws_vpc_security_group_egress_rule" "database" {
  security_group_id = aws_security_group.database.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow database outbound traffic"
}

resource "aws_vpc_security_group_egress_rule" "redis" {
  security_group_id = aws_security_group.redis.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow Redis outbound traffic"
}

resource "aws_db_subnet_group" "sub2api" {
  name       = "${var.name_prefix}-sub2api-postgres"
  subnet_ids = var.subnet_ids

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-sub2api-postgres"
  })
}

resource "aws_db_instance" "sub2api" {
  identifier = "${var.name_prefix}-sub2api-postgres"

  engine         = "postgres"
  instance_class = var.database_instance_class

  allocated_storage = var.database_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = local.database_name
  username = local.database_user
  password = random_password.database.result

  db_subnet_group_name   = aws_db_subnet_group.sub2api.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = var.database_multi_az

  backup_retention_period = var.database_backup_retention_period
  deletion_protection     = var.database_deletion_protection
  skip_final_snapshot     = var.database_skip_final_snapshot
  final_snapshot_identifier = (
    var.database_skip_final_snapshot ? null : "${var.name_prefix}-sub2api-postgres-final"
  )

  apply_immediately = var.database_apply_immediately

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-sub2api-postgres"
  })
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name_prefix}-sub2api-redis"
  subnet_ids = var.subnet_ids

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-sub2api-redis"
  })
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.name_prefix}-sub2api-redis"
  description          = "Redis for Sub2API scheduler and cache state"

  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.redis_node_type
  port                 = local.redis_port
  num_cache_clusters   = var.redis_num_cache_clusters
  parameter_group_name = "default.redis7"

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis.result

  automatic_failover_enabled = var.redis_num_cache_clusters > 1
  multi_az_enabled           = var.redis_num_cache_clusters > 1

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-sub2api-redis"
  })
}

resource "aws_service_discovery_http_namespace" "service_connect" {
  name        = local.namespace_name
  description = "Service Connect namespace for ${var.name_prefix}"

  tags = merge(local.tags, {
    Name = local.namespace_name
  })
}

resource "aws_ecs_task_definition" "sub2api" {
  family                   = "${var.name_prefix}-sub2api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = local.service_name
      image     = var.sub2api_image
      essential = true
      portMappings = [
        {
          name          = "http"
          containerPort = var.container_port
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      environment = [
        { name = "AUTO_SETUP", value = "true" },
        { name = "SERVER_HOST", value = "0.0.0.0" },
        { name = "SERVER_PORT", value = tostring(var.container_port) },
        { name = "SERVER_MODE", value = "release" },
        { name = "RUN_MODE", value = var.run_mode },
        { name = "DATABASE_HOST", value = aws_db_instance.sub2api.address },
        { name = "DATABASE_PORT", value = tostring(aws_db_instance.sub2api.port) },
        { name = "DATABASE_USER", value = local.database_user },
        { name = "DATABASE_DBNAME", value = local.database_name },
        { name = "DATABASE_SSLMODE", value = "require" },
        { name = "REDIS_HOST", value = aws_elasticache_replication_group.redis.primary_endpoint_address },
        { name = "REDIS_PORT", value = tostring(local.redis_port) },
        { name = "REDIS_ENABLE_TLS", value = "true" },
        { name = "ADMIN_EMAIL", value = var.admin_email },
        { name = "TZ", value = "UTC" },
        { name = "SECURITY_URL_ALLOWLIST_ENABLED", value = "true" },
        { name = "SECURITY_URL_ALLOWLIST_ALLOW_INSECURE_HTTP", value = "false" },
        { name = "SECURITY_URL_ALLOWLIST_ALLOW_PRIVATE_HOSTS", value = "false" },
        { name = "SECURITY_URL_ALLOWLIST_UPSTREAM_HOSTS", value = join(",", var.allowed_upstream_hosts) },
      ]
      secrets = [
        {
          name      = "DATABASE_PASSWORD"
          valueFrom = "${var.database_credentials_secret_arn}:password::"
        },
        {
          name      = "REDIS_PASSWORD"
          valueFrom = "${var.redis_auth_secret_arn}:auth_token::"
        },
        {
          name      = "JWT_SECRET"
          valueFrom = "${var.runtime_secret_arn}:jwt_secret::"
        },
        {
          name      = "TOTP_ENCRYPTION_KEY"
          valueFrom = "${var.runtime_secret_arn}:totp_encryption_key::"
        },
        {
          name      = "ADMIN_PASSWORD"
          valueFrom = "${var.admin_secret_arn}:password::"
        },
      ]
      healthCheck = {
        command     = ["CMD", "wget", "-q", "-T", "5", "-O", "/dev/null", "http://localhost:${var.container_port}/health"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 30
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "sub2api"
        }
      }
    }
  ])

  tags = merge(local.tags, {
    Name    = "${var.name_prefix}-sub2api"
    Service = local.service_name
  })
}

resource "aws_ecs_service" "sub2api" {
  name            = "${var.name_prefix}-sub2api"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.sub2api.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.sub2api.id]
    assign_public_ip = var.assign_public_ip
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.service_connect.arn

    service {
      port_name      = "http"
      discovery_name = "sub2api"

      client_alias {
        dns_name = "sub2api"
        port     = var.container_port
      }
    }
  }

  tags = merge(local.tags, {
    Name    = "${var.name_prefix}-sub2api"
    Service = local.service_name
  })

  depends_on = [
    aws_secretsmanager_secret_version.database,
    aws_secretsmanager_secret_version.redis,
    aws_secretsmanager_secret_version.runtime,
    aws_secretsmanager_secret_version.admin,
  ]
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.name_prefix}-sub2api-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = aws_ecs_service.sub2api.name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "${var.name_prefix}-sub2api-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = aws_ecs_service.sub2api.name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "database_cpu_high" {
  alarm_name          = "${var.name_prefix}-sub2api-postgres-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.sub2api.id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "redis_cpu_high" {
  alarm_name          = "${var.name_prefix}-sub2api-redis-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.redis.id
  }

  tags = local.tags
}

output "sub2api_service_name" {
  description = "ECS Sub2API service name."
  value       = aws_ecs_service.sub2api.name
}

output "sub2api_task_definition_arn" {
  description = "Sub2API task definition ARN."
  value       = aws_ecs_task_definition.sub2api.arn
}

output "sub2api_base_url" {
  description = "Service Connect HTTP base URL for Sub2API clients."
  value       = "http://sub2api:${var.container_port}"
}

output "service_connect_namespace_arn" {
  description = "Service Connect namespace ARN used by Sub2API."
  value       = aws_service_discovery_http_namespace.service_connect.arn
}

output "database_address" {
  description = "Sub2API Postgres endpoint address."
  value       = aws_db_instance.sub2api.address
}

output "redis_primary_endpoint_address" {
  description = "Sub2API Redis primary endpoint address."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "security_group_id" {
  description = "Sub2API task security group ID."
  value       = aws_security_group.sub2api.id
}
