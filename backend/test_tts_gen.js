const ttsService = require('./services/tts.service');

async function test() {
  console.log('Testing TTS generation...');
  const result = await ttsService.generateVietnameseTts('sched_test_954', 'Đã đến giờ làm bài tập rồi các bạn học sinh ơi!');
  console.log('Test result:', result);
}

test();
