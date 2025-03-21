# output "redis_subnet_group" {
#   description = "Subnet group name for Redis"
#   value       = aws_elasticache_subnet_group.this.name
# }
output "redis_security_group_id" {
  description = "Security Group ID for Redis"
  value       = aws_security_group.redis.id
}
output "redis_security_group_vpc_id" {
  value = aws_security_group.redis.vpc_id
}