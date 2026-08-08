const mqtt = require('mqtt');

const client = mqtt.connect('wss://mqtt.aiotlearninghub.com:443/mqtt', {
  clientId: 'test_trigger_' + Math.random().toString(16).slice(2, 8),
});

client.on('connect', () => {
  console.log('✅ Connected to MQTT broker!');

  // Set test schedule for 09:17
  const schedulePayload = JSON.stringify({
    schedules: [
      {
        id: 'sched_test_917',
        hour: 9,
        minute: 17,
        prompt: 'Xin chào các bạn học sinh, đây là thông báo tự động từ lịch 9 giờ 17 phút!',
        enabled: true,
        action: 'NONE'
      }
    ]
  });

  client.publish('cmnd/classroom_schedule/set', schedulePayload, () => {
    console.log('⏰ Đã publish cmnd/classroom_schedule/set cho mốc 09:17');
    setTimeout(() => {
      client.end();
      process.exit(0);
    }, 1500);
  });
});
