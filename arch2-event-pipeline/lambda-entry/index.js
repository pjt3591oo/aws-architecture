const { EventBridgeClient, PutEventsCommand } = require('@aws-sdk/client-eventbridge');

const client = new EventBridgeClient({
  endpoint: process.env.AWS_ENDPOINT_URL,
  region: process.env.AWS_REGION,
});

exports.handler = async (event) => {
  console.log('incoming event:', JSON.stringify(event));

  let body = {};
  try {
    body = event.body ? JSON.parse(event.body) : {};
  } catch (_) {
    body = {};
  }
  const orderId = body.orderId || `order-${Date.now()}`;

  const result = await client.send(new PutEventsCommand({
    Entries: [
      {
        Source: 'demo.api',
        DetailType: 'OrderCreated',
        Detail: JSON.stringify({ orderId, ...body }),
        EventBusName: 'default',
      },
    ],
  }));

  console.log('PutEvents result:', JSON.stringify(result));

  return {
    statusCode: 202,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: 'accepted', orderId }),
  };
};
