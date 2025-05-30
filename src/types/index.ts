export interface Quiz {
  id: string;
  title: string;
  description: string;
  creatorId: string;
  questions: Question[];
  createdAt: string;
  updatedAt: string;
}

export interface Question {
  id: string;
  text: string;
  choices: string[];
  correctAnswer: number;
  timeLimit: number; // seconds
  points: number;
}

export interface GameSession {
  id: string;
  quizId: string;
  hostId: string;
  joinCode: string;
  status: "waiting" | "active" | "finished";
  currentQuestionIndex: number;
  players: Player[];
  createdAt: string;
  startedAt?: string;
  finishedAt?: string;
  quiz?: Quiz;
}

export interface Player {
  id: string;
  name: string;
  sessionId: string;
  score: number;
  answers: PlayerAnswer[];
  isOnline: boolean;
  socketId?: string;
  joinedAt: string;
}

export interface PlayerAnswer {
  questionId: string;
  selectedChoice: number;
  timeToAnswer: number; // milliseconds
  isCorrect: boolean;
  points: number;
  submittedAt?: string; // ISO string timestamp when answer was submitted
}

export interface WebSocketMessage {
  type: MessageType;
  payload: any;
  sessionId: string;
  playerId?: string;
  timestamp: number;
}

export type MessageType =
  // Host messages
  | "host_join"
  | "start_game"
  | "next_question"
  | "reveal_answer"
  | "end_game"
  // Player messages
  | "player_join"
  | "submit_answer"
  // Broadcast messages
  | "player_joined"
  | "player_left"
  | "game_started"
  | "question_started"
  | "answer_revealed"
  | "game_ended"
  | "leaderboard_update"
  | "error"
  | "heartbeat";

export interface JoinPayload {
  playerName: string;
}

export interface HostJoinPayload {
  hostId: string;
  quizId: string;
}

export interface AnswerPayload {
  questionId: string;
  selectedChoice: number;
  timeToAnswer: number;
}

export interface NextQuestionPayload {
  question: Question;
  questionIndex: number;
  timeLimit: number;
}

export interface RevealAnswerPayload {
  correctAnswer: number;
  leaderboard: LeaderboardEntry[];
  question: Question;
}

export interface LeaderboardEntry {
  playerId: string;
  playerName: string;
  score: number;
  rank: number;
}

export interface ErrorPayload {
  message: string;
  code: string;
}

// Session data structure for backward compatibility
export interface SessionData {
  session: GameSession;
  hostSocketId?: string;
  playerSocketIds: { [playerId: string]: string };
} 