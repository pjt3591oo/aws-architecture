output "dev_invoke_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.api.id}/${aws_api_gateway_stage.dev.stage_name}/_user_request_/orders"
}

output "prod_invoke_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.api.id}/${aws_api_gateway_stage.prod.stage_name}/_user_request_/orders"
}

output "api_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "dev_queue_url" {
  value = module.dev.queue_url
}

output "prod_queue_url" {
  value = module.prod.queue_url
}

output "dev_table_name" {
  value = module.dev.table_name
}

output "prod_table_name" {
  value = module.prod.table_name
}

output "dev_event_bus_name" {
  value = module.dev.event_bus_name
}

output "prod_event_bus_name" {
  value = module.prod.event_bus_name
}
