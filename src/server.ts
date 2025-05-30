import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import express from 'express';
import cors from 'cors';
import gameService from './services/gameService';
import dynamoService from './services/dynamodb';

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

const server = createServer(app);
const wss = new WebSocketServer({ server });

interface QuizWebSocketMessage {
  type: string;
  content?: any;
  metadata?: any;
  timestamp: number;
  sessionId?: string;
  playerId?: string;
}

interface ExtendedWebSocket extends WebSocket {
  sessionId?: string;
  playerId?: string;
  isHost?: boolean;
  isAlive?: boolean;
}

const connections = new Map<string, ExtendedWebSocket>();

// 메시지 전송 헬퍼
function sendMessage(ws: ExtendedWebSocket, type: string, content?: any, metadata?: any): void {
  if (ws.readyState === WebSocket.OPEN) {
    const message: QuizWebSocketMessage = {
      type,
      content,
      metadata,
      timestamp: Date.now()
    };
    ws.send(JSON.stringify(message));
  }
}

// 세션의 모든 클라이언트에게 메시지 브로드캐스트
function broadcastToSession(sessionId: string, type: string, content?: any, excludeWs?: ExtendedWebSocket): void {
  connections.forEach((ws, connectionId) => {
    if (ws.sessionId === sessionId && ws !== excludeWs) {
      sendMessage(ws, type, content);
    }
  });
}

// 호스트에게만 메시지 전송
function sendToHost(sessionId: string, type: string, content?: any): void {
  connections.forEach((ws, connectionId) => {
    if (ws.sessionId === sessionId && ws.isHost) {
      sendMessage(ws, type, content);
    }
  });
}

// WebSocket 메시지 핸들러들
const messageHandlers: { [key: string]: (ws: ExtendedWebSocket, message: QuizWebSocketMessage) => Promise<void> } = {
  // 호스트 관련
  async host_join(ws: ExtendedWebSocket, message: QuizWebSocketMessage): Promise<void> {
    const { hostId, quizId } = message.content;
    console.log(`🎯 HOST_JOIN: Starting session creation for hostId=${hostId}, quizId=${quizId}`);
    console.log(`🎯 HOST_JOIN: Message content:`, JSON.stringify(message.content, null, 2));
    
    try {
      // 입력 검증
      if (!hostId || !quizId) {
        console.error(`❌ HOST_JOIN: Missing required parameters - hostId: ${hostId}, quizId: ${quizId}`);
        throw new Error('Missing hostId or quizId');
      }
      
      console.log(`📞 HOST_JOIN: Calling gameService.createSession...`);
      const session = await gameService.createSession(hostId, quizId);
      console.log(`📞 HOST_JOIN: gameService.createSession returned:`, session ? 'SUCCESS' : 'NULL');
      
      if (!session) {
        console.error(`❌ HOST_JOIN: Session creation failed - gameService returned null`);
        console.error(`❌ HOST_JOIN: This usually indicates quiz not found or DynamoDB error`);
        throw new Error('Failed to create session');
      }
      
      console.log(`✅ HOST_JOIN: Session created successfully:`, {
        sessionId: session.id,
        joinCode: session.joinCode,
        hostId: session.hostId,
        quizId: session.quizId,
        status: session.status
      });
      
      ws.sessionId = session.id;
      ws.playerId = hostId;
      ws.isHost = true;
      
      const connectionKey = `${session.id}-${hostId}`;
      connections.set(connectionKey, ws);
      console.log(`🔗 HOST_JOIN: Connection stored with key: ${connectionKey}`);
      
      console.log(`📤 HOST_JOIN: Sending session_created message to client...`);
      sendMessage(ws, 'session_created', session);
      console.log(`🎯 Host ${hostId} created session ${session.id} with join code ${session.joinCode}`);
      
    } catch (error) {
      console.error(`❌ HOST_JOIN: Error occurred:`, error);
      console.error(`❌ HOST_JOIN: Error stack:`, error instanceof Error ? error.stack : 'No stack trace');
      console.error(`❌ HOST_JOIN: Error name:`, error instanceof Error ? error.name : 'Unknown');
      console.error(`❌ HOST_JOIN: Error message:`, error instanceof Error ? error.message : 'Unknown error');
      
      // 에러 타입에 따른 더 자세한 정보 제공
      let errorMessage = 'Failed to create session';
      let errorCode = 'SESSION_CREATE_ERROR';
      
      if (error instanceof Error) {
        if (error.message.includes('Quiz') && error.message.includes('not found')) {
          errorMessage = `Quiz ${quizId} not found`;
          errorCode = 'QUIZ_NOT_FOUND';
        } else if (error.message.includes('Missing')) {
          errorMessage = 'Missing required parameters';
          errorCode = 'MISSING_PARAMETERS';
        }
      }
      
      sendMessage(ws, 'error', { 
        message: errorMessage, 
        code: errorCode,
        details: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  },

  // 플레이어 관련
  async player_join(ws: ExtendedWebSocket, message: QuizWebSocketMessage): Promise<void> {
    const { playerName } = message.content;
    const joinCode = message.sessionId!;
    
    console.log(`👤 SERVER: Player join attempt - Name: ${playerName}, Join Code: ${joinCode}`);
    
    try {
      console.log(`🔍 SERVER: Calling gameService.joinSession...`);
      const result = await gameService.joinSession(joinCode, playerName);
      console.log(`🔍 SERVER: gameService.joinSession result:`, result ? 'SUCCESS' : 'NULL');
      
      if (!result) {
        console.error(`❌ SERVER: Failed to join session - gameService returned null`);
        throw new Error('Failed to join session');
      }
      
      const { session, player } = result;
      console.log(`✅ SERVER: Player join successful:`, {
        playerId: player.id,
        playerName: player.name,
        sessionId: session.id,
        sessionStatus: session.status
      });
      
      ws.sessionId = session.id;
      ws.playerId = player.id;
      ws.isHost = false;
      
      const connectionKey = `${session.id}-${player.id}`;
      connections.set(connectionKey, ws);
      console.log(`🔗 SERVER: Player connection stored with key: ${connectionKey}`);
      
      console.log(`📤 SERVER: Sending player_joined_success to player...`);
      // 플레이어에게 성공 응답
      const responseData: any = { session, player };
      
      // 이름이 변경된 경우 알림 추가
      if (player.name !== playerName) {
        responseData.nameChanged = {
          original: playerName,
          final: player.name,
          reason: "이름 중복으로 인한 자동 변경"
        };
      }
      
      sendMessage(ws, 'player_joined_success', responseData);
      
      console.log(`📤 SERVER: Notifying host about new player...`);
      // 호스트에게 새 플레이어 알림
      sendToHost(session.id, 'player_joined', player);
      
      console.log(`🎯 SERVER: Player ${playerName} successfully joined session ${session.id}`);
      
    } catch (error) {
      console.error('❌ SERVER: Player join error:', error);
      console.error('❌ SERVER: Error stack:', error instanceof Error ? error.stack : 'No stack trace');
      sendMessage(ws, 'error', { 
        message: 'Failed to join session', 
        code: 'SESSION_JOIN_ERROR',
        details: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  },

  // 게임 시작
  async start_game(ws: ExtendedWebSocket, message: QuizWebSocketMessage): Promise<void> {
    if (!ws.isHost) {
      sendMessage(ws, 'error', { message: 'Only host can start game', code: 'UNAUTHORIZED' });
      return;
    }

    try {
      const success = await gameService.startGame(message.sessionId!, message.playerId!);
      
      if (!success) {
        throw new Error('Failed to start game');
      }
      
      // Get first question
      const question = await gameService.nextQuestion(message.sessionId!, message.playerId!);
      if (!question) {
        throw new Error('No questions available');
      }
      
      const gameData = {
        question,
        questionIndex: 1,
        timeLimit: question.timeLimit
      };
      
      console.log(`🎮 Game started in session ${message.sessionId}`);
      
      // 모든 참가자에게 게임 시작 알림
      broadcastToSession(message.sessionId!, 'game_started', gameData);
      
    } catch (error) {
      console.error('Start game error:', error);
      sendMessage(ws, 'error', { 
        message: 'Failed to start game', 
        code: 'GAME_START_ERROR' 
      });
    }
  },

  // 다음 문제
  async next_question(ws: ExtendedWebSocket, message: QuizWebSocketMessage): Promise<void> {
    if (!ws.isHost) {
      sendMessage(ws, 'error', { message: 'Only host can proceed to next question', code: 'UNAUTHORIZED' });
      return;
    }

    try {
      const question = await gameService.nextQuestion(message.sessionId!, message.playerId!);
      
      if (!question) {
        // Game finished - wait for finish game to complete before sending final leaderboard
        console.log(`🏁 SERVER: Game finished for session ${message.sessionId}, getting final leaderboard...`);
        
        // finishGame is already called in nextQuestion method, so just get the leaderboard
        const leaderboard = await gameService.getLeaderboard(message.sessionId!);
        
        console.log(`📊 SERVER: Final leaderboard retrieved with ${leaderboard.length} entries`);
        console.log(`🎯 SERVER: Broadcasting game_ended event to all participants`);
        
        broadcastToSession(message.sessionId!, 'game_ended', leaderboard);
        return;
      }
      
      const gameData = {
        question,
        questionIndex: question.id,
        timeLimit: question.timeLimit
      };
      
      console.log(`❓ Next question in session ${message.sessionId}`);
      
      // 모든 참가자에게 새 문제 전송
      broadcastToSession(message.sessionId!, 'question_started', gameData);
      
    } catch (error) {
      console.error('Next question error:', error);
      sendMessage(ws, 'error', { 
        message: 'Failed to load next question', 
        code: 'NEXT_QUESTION_ERROR' 
      });
    }
  },

  // 답안 제출
  async submit_answer(ws: ExtendedWebSocket, message: QuizWebSocketMessage): Promise<void> {
    const { questionId, selectedChoice, timeToAnswer } = message.content;
    
    console.log(`📝 SERVER: Player ${message.playerId} submitting answer for question ${questionId}, choice: ${selectedChoice}`);
    
    try {
      const result = await gameService.submitAnswer(
        message.sessionId!,
        message.playerId!,
        questionId,
        selectedChoice,
        timeToAnswer
      );
      
      if (!result) {
        console.error(`❌ SERVER: Answer submission failed for player ${message.playerId}`);
        throw new Error('Failed to submit answer');
      }
      
      console.log(`✅ SERVER: Answer submitted successfully by ${message.playerId}:`, result);
      
      // 플레이어에게 제출 결과 전송
      sendMessage(ws, 'answer_submitted', result);
      
      // 호스트에게 플레이어가 답변했음을 알림
      sendToHost(message.sessionId!, 'player_answered', {
        playerId: message.playerId,
        playerName: 'Player', // 실제로는 플레이어 이름을 가져와야 함
        hasAnswered: true
      });
      
    } catch (error) {
      console.error('❌ SERVER: Submit answer error:', error);
      sendMessage(ws, 'error', { 
        message: 'Failed to submit answer', 
        code: 'SUBMIT_ANSWER_ERROR',
        details: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  },

  // 정답 공개
  async reveal_answer(ws: ExtendedWebSocket, message: QuizWebSocketMessage): Promise<void> {
    if (!ws.isHost) {
      sendMessage(ws, 'error', { message: 'Only host can reveal answers', code: 'UNAUTHORIZED' });
      return;
    }

    try {
      console.log(`💡 SERVER: Revealing answer for session ${message.sessionId}`);
      
      // 현재 세션 정보 가져오기
      const session = await gameService.getSession(message.sessionId!);
      if (!session) {
        throw new Error('Session not found');
      }
      
      // 현재 문제 정보 가져오기 (이전 문제의 인덱스)
      const currentQuestionIndex = Math.max(0, (session.currentQuestionIndex || 1) - 1);
      const currentQuestion = session.quiz?.questions[currentQuestionIndex];
      
      if (!currentQuestion) {
        throw new Error('Current question not found');
      }
      
      console.log(`💡 SERVER: Revealing answer for question: ${currentQuestion.id} - "${currentQuestion.text}"`);
      console.log(`💡 SERVER: Correct answer: ${currentQuestion.correctAnswer} (${currentQuestion.choices[currentQuestion.correctAnswer]})`);
      
      // 모든 플레이어의 답변 통계 계산
      const players = await gameService.getSessionPlayers(message.sessionId!);
      const questionAnswers = players.map((player: any) => 
        player.answers.find((answer: any) => answer.questionId === currentQuestion.id)
      ).filter((answer: any) => answer !== undefined);
      
      const correctAnswers = questionAnswers.filter((answer: any) => answer!.isCorrect);
      const answerStats = currentQuestion.choices.map((choice: string, index: number) => ({
        choiceIndex: index,
        choiceText: choice,
        count: questionAnswers.filter((answer: any) => answer!.selectedChoice === index).length,
        isCorrect: index === currentQuestion.correctAnswer
      }));
      
      console.log(`📊 SERVER: Answer statistics:`, answerStats);
      console.log(`✅ SERVER: ${correctAnswers.length}/${questionAnswers.length} players answered correctly`);
      
      const leaderboard = await gameService.getLeaderboard(message.sessionId!);
      
      const result = {
        question: currentQuestion,
        correctAnswer: currentQuestion.correctAnswer,
        correctAnswerText: currentQuestion.choices[currentQuestion.correctAnswer],
        answerStats,
        correctCount: correctAnswers.length,
        totalAnswers: questionAnswers.length,
        leaderboard
      };
      
      console.log(`💡 SERVER: Answer revealed in session ${message.sessionId}`);
      
      // 모든 참가자에게 정답과 통계 전송
      broadcastToSession(message.sessionId!, 'answer_revealed', result);
      
    } catch (error) {
      console.error('❌ SERVER: Reveal answer error:', error);
      sendMessage(ws, 'error', { 
        message: 'Failed to reveal answer', 
        code: 'REVEAL_ANSWER_ERROR',
        details: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  },

  // 세션 결과 조회
  async get_session_results(ws: ExtendedWebSocket, message: QuizWebSocketMessage): Promise<void> {
    const { sessionId } = message.content;
    
    console.log(`📊 SERVER: Getting session results for ${sessionId}`);
    
    try {
      const results = await gameService.getSessionResults(sessionId);
      
      if (!results) {
        console.error(`❌ SERVER: No session results found for ${sessionId}`);
        sendMessage(ws, 'session_results', null);
        return;
      }
      
      console.log(`✅ SERVER: Session results retrieved for ${sessionId}`);
      
      // 요청한 클라이언트에게 결과 전송
      sendMessage(ws, 'session_results', results);
      
    } catch (error) {
      console.error('❌ SERVER: Get session results error:', error);
      sendMessage(ws, 'error', { 
        message: 'Failed to get session results', 
        code: 'GET_SESSION_RESULTS_ERROR',
        details: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  },

  // Ping-Pong
  async ping(ws: ExtendedWebSocket, message: QuizWebSocketMessage): Promise<void> {
    sendMessage(ws, 'pong');
  },

  // 공개 게임 결과 목록 조회
  async get_public_game_results(ws: ExtendedWebSocket, message: QuizWebSocketMessage): Promise<void> {
    const { quizTitle, limit } = message.content;
    
    console.log(`🌐 SERVER: Getting public game results`);
    
    try {
      const gameResults = await dynamoService.getPublicGameResults(quizTitle, limit || 20);
      sendMessage(ws, 'public_game_results', gameResults);
    } catch (error) {
      console.error('Error getting public game results:', error);
      sendMessage(ws, 'error', { message: 'Failed to get public game results' });
    }
  },

  // 특정 게임 결과 조회
  async get_game_result(ws: ExtendedWebSocket, message: QuizWebSocketMessage): Promise<void> {
    const { sessionId } = message.content;
    
    console.log(`🎯 SERVER: Getting game result for session ${sessionId}`);
    
    try {
      const gameResult = await dynamoService.getGameResult(sessionId);
      if (gameResult) {
        sendMessage(ws, 'game_result', gameResult);
      } else {
        sendMessage(ws, 'error', { message: 'Game result not found' });
      }
    } catch (error) {
      console.error('Error getting game result:', error);
      sendMessage(ws, 'error', { message: 'Failed to get game result' });
    }
  },

  // 게임 수동 종료
  async finish_game(ws: ExtendedWebSocket, message: QuizWebSocketMessage): Promise<void> {
    if (!ws.isHost) {
      sendMessage(ws, 'error', { message: 'Only host can finish the game', code: 'UNAUTHORIZED' });
      return;
    }

    try {
      console.log(`🏁 SERVER: Manual game finish requested for session ${message.sessionId} by host ${message.playerId}`);
      
      // 게임 종료 처리
      const success = await gameService.finishGame(message.sessionId!);
      
      if (success) {
        console.log(`✅ SERVER: Game finished successfully for session ${message.sessionId}`);
        
        // 최종 리더보드 가져오기
        const leaderboard = await gameService.getLeaderboard(message.sessionId!);
        
        console.log(`📊 SERVER: Broadcasting game_ended event with ${leaderboard.length} players`);
        
        // 모든 참가자에게 게임 종료 알림
        broadcastToSession(message.sessionId!, 'game_ended', leaderboard);
        
        console.log(`🎯 SERVER: Manual game finish completed for session ${message.sessionId}`);
      } else {
        console.error(`❌ SERVER: Failed to finish game for session ${message.sessionId}`);
        sendMessage(ws, 'error', { message: 'Failed to finish game', code: 'FINISH_GAME_ERROR' });
      }
    } catch (error) {
      console.error('❌ SERVER: Error finishing game:', error);
      sendMessage(ws, 'error', { message: 'Failed to finish game', code: 'FINISH_GAME_ERROR' });
    }
  }
};

// WebSocket 연결 처리
wss.on('connection', (ws: WebSocket) => {
  const extendedWs = ws as ExtendedWebSocket;
  extendedWs.isAlive = true;
  
  const connectionId = Math.random().toString(36).substring(2, 8);
  console.log(`🔗 SERVER: New connection established with ID: ${connectionId}`);
  
  // 메시지 수신 처리
  extendedWs.on('message', async (data: Buffer) => {
    try {
      console.log(`📨 SERVER: Received message from ${connectionId}:`, data.toString());
      const message: QuizWebSocketMessage = JSON.parse(data.toString());
      console.log(`📨 SERVER: Parsed message type: ${message.type}`, {
        type: message.type,
        hasContent: !!message.content,
        contentKeys: message.content ? Object.keys(message.content) : 'none',
        sessionId: message.sessionId,
        playerId: message.playerId
      });
      
      // 메시지 타입에 따라 적절한 핸들러 호출
      if (messageHandlers[message.type]) {
        console.log(`🎯 SERVER: Calling handler for message type: ${message.type}`);
        await messageHandlers[message.type](extendedWs, message);
      } else {
        console.warn(`⚠️ SERVER: Unknown message type: ${message.type}`);
        sendMessage(extendedWs, 'error', { 
          message: `Unknown message type: ${message.type}`, 
          code: 'UNKNOWN_MESSAGE_TYPE' 
        });
      }
    } catch (error) {
      console.error(`❌ SERVER: Error processing message from ${connectionId}:`, error);
      console.error(`❌ SERVER: Raw message data:`, data.toString());
      sendMessage(extendedWs, 'error', { 
        message: 'Invalid message format', 
        code: 'INVALID_MESSAGE_FORMAT',
        details: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  });
  
  // 연결 종료 처리
  extendedWs.on('close', (code: number, reason: Buffer) => {
    console.log(`🔌 SERVER: Connection ${connectionId} closed - Code: ${code}, Reason: ${reason.toString()}`);
    
    // 연결 맵에서 제거
    connections.forEach((connection, key) => {
      if (connection === extendedWs) {
        connections.delete(key);
        console.log(`🧹 SERVER: Removed connection ${key} from connections map`);
      }
    });
    
    // DynamoDB에서 소켓 정보 정리
    if (extendedWs.sessionId) {
      dynamoService.removeSocket(extendedWs.sessionId, connectionId);
    }
  });
  
  // 에러 처리
  extendedWs.on('error', (error: Error) => {
    console.error(`❌ SERVER: WebSocket error for connection ${connectionId}:`, error);
  });
  
  // Heartbeat
  extendedWs.on('pong', () => {
    extendedWs.isAlive = true;
  });
});

server.listen(PORT, () => {
  console.log(`🚀 SERVER: Server is running on port ${PORT}`);
});