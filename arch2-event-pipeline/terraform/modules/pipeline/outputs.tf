output "queue_url" {
  value = aws_sqs_queue.order_queue.id
}

output "table_name" {
  value = aws_dynamodb_table.orders.name
}

output "event_bus_name" {
  value = aws_cloudwatch_event_bus.order_bus.name
}

output "entry_lambda_name" {
  value = aws_lambda_function.entry.function_name
}

output "consumer_lambda_name" {
  value = aws_lambda_function.consumer.function_name
}
