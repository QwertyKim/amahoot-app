import { Quiz, Question } from './types';

export const DEMO_QUIZ_ID = 'demo-quiz-2024';
export const DEMO_HOST_ID = 'demo-host-user';

export const demoQuestions: Question[] = [
  {
    id: 'q1',
    text: '대한민국의 수도는 어디인가요?',
    choices: ['서울', '부산', '대구', '인천'],
    correctAnswer: 0,
    timeLimit: 15,
    points: 100
  },
  {
    id: 'q2', 
    text: '다음 중 프로그래밍 언어가 아닌 것은?',
    choices: ['JavaScript', 'Python', 'HTML', 'Java'],
    correctAnswer: 2,
    timeLimit: 20,
    points: 150
  },
  {
    id: 'q3',
    text: '1 + 1 = ?',
    choices: ['1', '2', '3', '11'],
    correctAnswer: 1,
    timeLimit: 10,
    points: 50
  },
  {
    id: 'q4',
    text: '지구에서 가장 큰 대륙은?',
    choices: ['아프리카', '아시아', '유럽', '북아메리카'],
    correctAnswer: 1,
    timeLimit: 25,
    points: 200
  },
  {
    id: 'q5',
    text: 'React는 무엇을 위한 라이브러리인가요?',
    choices: ['데이터베이스', '서버', '사용자 인터페이스', '네트워킹'],
    correctAnswer: 2,
    timeLimit: 30,
    points: 250
  }
];

export const demoQuiz: Quiz = {
  id: DEMO_QUIZ_ID,
  title: '🎯 Amahoot 데모 퀴즈',
  description: '실시간 퀴즈 시스템을 체험해보세요! 일반 상식부터 프로그래밍까지 다양한 문제가 준비되어 있습니다.',
  creatorId: DEMO_HOST_ID,
  questions: demoQuestions,
  createdAt: new Date().toISOString(),
  updatedAt: new Date().toISOString()
};

// 데모 퀴즈인지 확인하는 함수
export function isDemoQuiz(quizId: string): boolean {
  return quizId === DEMO_QUIZ_ID;
} 