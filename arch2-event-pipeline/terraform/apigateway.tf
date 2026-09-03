# 하나의 REST API(demo-api)에 dev/prod 두 스테이지를 두고,
# 실제로 호출되는 Lambda는 스테이지 변수(lambdaFunction)로 갈라지도록 구성한다.
#
# REST API의 통합(integration)은 메서드당 1개뿐이라 스테이지별로 따로 만들
# 수 없다. 그래서 통합 URI 안에 실제 함수 이름 대신 ${stageVariables.lambdaFunction}
# 를 넣고, 스테이지마다 이 변수 값을 다르게 준다 (dev 스테이지 -> demo-entry-lambda-dev,
# prod 스테이지 -> demo-entry-lambda-prod).

resource "aws_api_gateway_rest_api" "api" {
  name = "demo-api"
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "orders"
}

resource "aws_api_gateway_method" "post_orders" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.orders.id
  http_method             = aws_api_gateway_method.post_orders.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"

  # $$ 는 terraform 문자열 보간 이스케이프. 실제로 AWS에 전달되는 값은
  # ".../functions/arn:aws:lambda:...:function:${stageVariables.lambdaFunction}/invocations"
  uri = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.aws_region}:${var.account_id}:function:$${stageVariables.lambdaFunction}/invocations"
}

# 스테이지마다 실제로 호출될 함수가 다르므로, 두 함수 모두에 대해
# API Gateway가 호출할 수 있도록 권한을 각각 부여한다.
resource "aws_lambda_permission" "apigw_invoke_dev" {
  statement_id  = "apigw-invoke-dev"
  action        = "lambda:InvokeFunction"
  function_name = module.dev.entry_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${var.account_id}:${aws_api_gateway_rest_api.api.id}/*/POST/orders"
}

resource "aws_lambda_permission" "apigw_invoke_prod" {
  statement_id  = "apigw-invoke-prod"
  action        = "lambda:InvokeFunction"
  function_name = module.prod.entry_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${var.account_id}:${aws_api_gateway_rest_api.api.id}/*/POST/orders"
}

resource "aws_api_gateway_deployment" "deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.orders.id,
      aws_api_gateway_method.post_orders.id,
      aws_api_gateway_integration.lambda.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_lambda_permission.apigw_invoke_dev,
    aws_lambda_permission.apigw_invoke_prod,
  ]
}

resource "aws_api_gateway_stage" "dev" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deploy.id
  stage_name    = "dev"

  variables = {
    lambdaFunction = module.dev.entry_lambda_name
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deploy.id
  stage_name    = "prod"

  variables = {
    lambdaFunction = module.prod.entry_lambda_name
  }
}
