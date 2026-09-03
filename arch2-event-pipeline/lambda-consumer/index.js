const { DynamoDBClient, PutItemCommand } = require('@aws-sdk/client-dynamodb');

const client = new DynamoDBClient({
  endpoint: process.env.AWS_ENDPOINT_URL,
  region: process.env.AWS_REGION,
});

exports.handler = async (event) => {
  console.log('incoming SQS event:', JSON.stringify(event));

  for (const record of event.Records) {
    const sqsBody = JSON.parse(record.body);
    // EventBridge -> SQS 로 전달되는 메시지는 EventBridge 이벤트 엔벨로프 그대로 오고,
    // 우리가 PutEvents에 넣은 실제 페이로드는 그 안의 "detail" 필드에 들어있음.
    const detail = sqsBody.detail || sqsBody;

    await client.send(new PutItemCommand({
      TableName: 'Orders',
      Item: {
        orderId: { S: String(detail.orderId) },
        payload: { S: JSON.stringify(detail) },
        processedAt: { S: new Date().toISOString() },
      },
    }));

    console.log('saved to DynamoDB:', detail.orderId);
  }

  return { batchItemFailures: [] };
};
