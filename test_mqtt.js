const mqtt = require('mqtt');

const client = mqtt.connect('wss://mqtt.aiotlearninghub.com:443/mqtt', {
  clientId: 'test_node_client_' + Math.random().toString(16).substr(2, 8),
});

client.on('connect', () => {
  console.log('✅ Connected to MQTT broker via WSS!');
  client.subscribe('tele/#', (err) => {
    if (!err) {
      console.log('✅ Subscribed to tele/#');
    }
  });
});

client.on('message', (topic, message) => {
  console.log(`📩 [${topic}] ${message.toString()}`);
});

client.on('error', (error) => {
  console.error('❌ Connection error:', error);
});

client.on('offline', () => {
  console.log('⚠️ Client went offline');
});
