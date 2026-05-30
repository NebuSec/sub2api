output "sub2api_service_name" {
  description = "Prod Sub2API ECS service name."
  value       = module.sub2api_service.sub2api_service_name
}

output "sub2api_task_definition_arn" {
  description = "Prod Sub2API ECS task definition ARN."
  value       = module.sub2api_service.sub2api_task_definition_arn
}

output "sub2api_base_url" {
  description = "Service Connect HTTP base URL for Sub2API clients."
  value       = module.sub2api_service.sub2api_base_url
}

output "sub2api_security_group_id" {
  description = "Sub2API task security group ID."
  value       = module.sub2api_service.security_group_id
}

output "service_connect_namespace_arn" {
  description = "Service Connect namespace ARN used by Sub2API."
  value       = module.sub2api_service.service_connect_namespace_arn
}

output "cloudflared_sub2api_service_name" {
  description = "Prod Cloudflare Tunnel ECS service name for Sub2API admin access."
  value       = aws_ecs_service.cloudflared_sub2api.name
}

output "cloudflared_sub2api_task_definition_arn" {
  description = "Prod Cloudflare Tunnel ECS task definition ARN for Sub2API admin access."
  value       = aws_ecs_task_definition.cloudflared_sub2api.arn
}
