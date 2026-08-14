const mqtt = require('mqtt');

const client = mqtt.connect('wss://mqtt.duynguyen.io.vn:443/mqtt');

client.on('connect', () => {
  console.log('Connected to mqtt.duynguyen.io.vn for test publish...');
  const payload = JSON.stringify({
    schedules: [
      {
        id: 'sched_morning',
        hour: 11,
        minute: 23,
        prompt: 'Đã đến giờ truy bài, các bạn học sinh chuẩn bị vào lớp!',
        enabled: true,
        action: 'NONE'
      }
    ]
  });
  client.publish('cmnd/classroom_schedule/set', payload, () => {
    console.log('Successfully published test schedule 11:23 to cmnd/classroom_schedule/set!');
    setTimeout(() => {
      client.end();
      process.exit(0);
    }, 1000);
  });
});
