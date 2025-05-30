import { v4 as uuidv4 } from 'uuid';
import dynamoService from './dynamodb';
import type { GameResult } from './dynamodb';
import { 
  GameSession, 
  Player, 
  Quiz, 
  Question, 
  PlayerAnswer, 
  LeaderboardEntry, 
  SessionData 
} from '../types';

class GameService {
  private generateJoinCode(): string {
    return Math.random().toString(36).substring(2, 8).toUpperCase();
  }

  async createSession(hostId: string, quizId: string): Promise<GameSession | null> {
    console.log(`🏗️ GAME_SERVICE: createSession called with hostId=${hostId}, quizId=${quizId}`);
    
    try {
      console.log(`📚 GAME_SERVICE: Fetching quiz from DynamoDB...`);
      // Get quiz from DynamoDB
      const quiz = await dynamoService.getQuiz(quizId);
      console.log(`📚 GAME_SERVICE: Quiz fetch result:`, quiz ? 'FOUND' : 'NOT_FOUND');
      
      if (!quiz) {
        console.error(`❌ GAME_SERVICE: Quiz ${quizId} not found in DynamoDB`);
        return null;
      }

      console.log(`🎲 GAME_SERVICE: Starting join code generation...`);
      // Generate unique join code
      let joinCode: string;
      let isUnique = false;
      let attempts = 0;
      
      do {
        joinCode = this.generateJoinCode();
        console.log(`🎲 GAME_SERVICE: Generated join code attempt ${attempts + 1}: ${joinCode}`);
        
        const existingSession = await dynamoService.getSessionByJoinCode(joinCode);
        isUnique = !existingSession;
        console.log(`🔍 GAME_SERVICE: Join code uniqueness check: ${isUnique ? 'UNIQUE' : 'DUPLICATE'}`);
        
        attempts++;
      } while (!isUnique && attempts < 10);

      if (!isUnique) {
        console.error(`❌ GAME_SERVICE: Could not generate unique join code after ${attempts} attempts`);
        throw new Error('Could not generate unique join code');
      }

      console.log(`✅ GAME_SERVICE: Unique join code generated: ${joinCode} (after ${attempts} attempts)`);

      const sessionId = uuidv4();
      console.log(`🆔 GAME_SERVICE: Generated session ID: ${sessionId}`);
      
      const session: GameSession = {
        id: sessionId,
        quizId,
        hostId,
        joinCode: joinCode!,
        status: 'waiting',
        currentQuestionIndex: 0,
        players: [],
        createdAt: new Date().toISOString(),
        quiz
      };

      console.log(`💾 GAME_SERVICE: Saving session to DynamoDB...`);
      // Save to DynamoDB
      await dynamoService.saveSession(session);
      console.log(`💾 GAME_SERVICE: Setting join code mapping...`);
      await dynamoService.setJoinCode(joinCode!, sessionId);
      console.log(`✅ GAME_SERVICE: Session created and saved successfully`);

      return session;
    } catch (error) {
      console.error(`❌ GAME_SERVICE: Error creating session:`, error);
      console.error(`❌ GAME_SERVICE: Error stack:`, error instanceof Error ? error.stack : 'No stack trace');
      return null;
    }
  }

  async joinSession(joinCode: string, playerName: string): Promise<{ session: GameSession; player: Player } | null> {
    console.log(`🎮 GAME_SERVICE: joinSession called with joinCode=${joinCode}, playerName=${playerName}`);
    
    try {
      console.log(`🔍 GAME_SERVICE: Looking up session by join code...`);
      // Get session by join code
      const sessionId = await dynamoService.getSessionByJoinCode(joinCode);
      console.log(`🔍 GAME_SERVICE: Join code lookup result:`, sessionId ? sessionId : 'NOT_FOUND');
      
      if (!sessionId) {
        console.error(`❌ GAME_SERVICE: Invalid join code: ${joinCode}`);
        throw new Error('Invalid join code');
      }

      console.log(`📋 GAME_SERVICE: Fetching session details for ${sessionId}...`);
      const session = await dynamoService.getSession(sessionId);
      console.log(`📋 GAME_SERVICE: Session fetch result:`, session ? 'FOUND' : 'NOT_FOUND');
      
      if (!session) {
        console.error(`❌ GAME_SERVICE: Session not found: ${sessionId}`);
        throw new Error('Session not found');
      }

      console.log(`🎯 GAME_SERVICE: Session status check - Current: ${session.status}, Required: waiting`);
      // Check if game has started
      if (session.status !== 'waiting') {
        console.error(`❌ GAME_SERVICE: Game has already started. Status: ${session.status}`);
        throw new Error('Game has already started');
      }

      console.log(`👥 GAME_SERVICE: Getting current players for session ${sessionId}...`);
      // Get current players
      let players = await dynamoService.getSessionPlayers(sessionId);
      console.log(`👥 GAME_SERVICE: Found ${players.length} existing players`);

      // Check if player name is already taken and generate unique name
      let uniquePlayerName = playerName;
      let nameCounter = 1;
      
      while (players.find(p => p.name === uniquePlayerName)) {
        nameCounter++;
        uniquePlayerName = `${playerName}${nameCounter}`;
        console.log(`🔄 GAME_SERVICE: Trying alternative name: ${uniquePlayerName}`);
      }
      
      if (uniquePlayerName !== playerName) {
        console.log(`✏️ GAME_SERVICE: Player name changed from "${playerName}" to "${uniquePlayerName}" to avoid duplicates`);
      }

      // 대안: 고유 식별자 사용
      // const shortId = Math.random().toString(36).substring(2, 6).toUpperCase();
      // if (players.find(p => p.name === playerName)) {
      //   uniquePlayerName = `${playerName} #${shortId}`;
      //   console.log(`✏️ GAME_SERVICE: Added unique identifier: ${uniquePlayerName}`);
      // }

      // Create new player
      const playerId = uuidv4();
      console.log(`🆔 GAME_SERVICE: Generated player ID: ${playerId}`);
      
      const player: Player = {
        id: playerId,
        name: uniquePlayerName,
        sessionId,
        score: 0,
        answers: [],
        isOnline: true,
        joinedAt: new Date().toISOString()
      };

      console.log(`💾 GAME_SERVICE: Saving new player to DynamoDB...`);
      // Save player to DynamoDB
      await dynamoService.savePlayer(sessionId, player);
      console.log(`✅ GAME_SERVICE: Player saved to DynamoDB successfully`);

      // Update session with current players
      session.players = [...players, player];
      console.log(`📊 GAME_SERVICE: Updated session players count: ${session.players.length}`);

      console.log(`🎉 GAME_SERVICE: Player ${playerName} successfully joined session ${sessionId}`);
      return { session, player };
    } catch (error) {
      console.error('❌ GAME_SERVICE: Error joining session:', error);
      console.error('❌ GAME_SERVICE: Error stack:', error instanceof Error ? error.stack : 'No stack trace');
      return null;
    }
  }

  async startGame(sessionId: string, hostId: string): Promise<boolean> {
    try {
      const session = await dynamoService.getSession(sessionId);
      if (!session) {
        throw new Error('Session not found');
      }

      if (session.hostId !== hostId) {
        throw new Error('Only host can start the game');
      }

      if (session.status !== 'waiting') {
        throw new Error('Game has already started');
      }

      const players = await dynamoService.getSessionPlayers(sessionId);
      if (players.length === 0) {
        throw new Error('No players joined');
      }

      // Update session status
      await dynamoService.updateSession(sessionId, { 
        status: 'active', 
        startedAt: new Date().toISOString() 
      });

      return true;
    } catch (error) {
      console.error('Error starting game:', error);
      return false;
    }
  }

  async nextQuestion(sessionId: string, hostId: string): Promise<Question | null> {
    console.log(`❓ GAME_SERVICE: nextQuestion called for session ${sessionId} by host ${hostId}`);
    
    try {
      const session = await dynamoService.getSession(sessionId);
      if (!session) {
        console.error(`❌ GAME_SERVICE: Session ${sessionId} not found`);
        throw new Error('Session not found');
      }

      if (session.hostId !== hostId) {
        console.error(`❌ GAME_SERVICE: Host ID mismatch. Expected: ${session.hostId}, Got: ${hostId}`);
        throw new Error('Only host can control questions');
      }

      if (session.status !== 'active') {
        console.error(`❌ GAME_SERVICE: Game is not active. Current status: ${session.status}`);
        throw new Error('Game is not active');
      }

      const quiz = session.quiz;
      if (!quiz) {
        console.error(`❌ GAME_SERVICE: Quiz not found in session ${sessionId}`);
        throw new Error('Quiz not found in session');
      }

      console.log(`📊 GAME_SERVICE: Current question index: ${session.currentQuestionIndex}, Total questions: ${quiz.questions.length}`);
      
      // 현재 인덱스의 문제를 반환하고, 다음 호출을 위해 인덱스 증가
      const currentIndex = session.currentQuestionIndex;
      
      if (currentIndex >= quiz.questions.length) {
        console.log(`🏁 GAME_SERVICE: All questions completed. Finishing game.`);
        await this.finishGame(sessionId);
        return null;
      }

      const question = quiz.questions[currentIndex];
      console.log(`❓ GAME_SERVICE: Serving question: ${question.id} - "${question.text}"`);
      
      // 다음 문제를 위해 인덱스 증가
      const nextIndex = currentIndex + 1;
      await dynamoService.updateSession(sessionId, { currentQuestionIndex: nextIndex });
      console.log(`💾 GAME_SERVICE: Updated currentQuestionIndex from ${currentIndex} to ${nextIndex}`);

      return question;
    } catch (error) {
      console.error('❌ GAME_SERVICE: Error getting next question:', error);
      return null;
    }
  }

  async submitAnswer(sessionId: string, playerId: string, questionId: string, selectedChoice: number, timeToAnswer: number): Promise<{ isCorrect: boolean; points: number; questionId: string; rank?: number; totalCorrect?: number } | null> {
    console.log(`📝 GAME_SERVICE: submitAnswer called for session ${sessionId}, player ${playerId}, question ${questionId}, choice ${selectedChoice}`);
    
    try {
      const session = await dynamoService.getSession(sessionId);
      if (!session) {
        console.error(`❌ GAME_SERVICE: Session ${sessionId} not found`);
        throw new Error('Session not found');
      }

      if (session.status !== 'active') {
        console.error(`❌ GAME_SERVICE: Game is not active. Current status: ${session.status}`);
        throw new Error('Game is not active');
      }

      const quiz = session.quiz;
      if (!quiz) {
        console.error(`❌ GAME_SERVICE: Quiz not found in session ${sessionId}`);
        throw new Error('Quiz not found');
      }

      const question = quiz.questions.find(q => q.id === questionId);
      if (!question) {
        console.error(`❌ GAME_SERVICE: Question ${questionId} not found in quiz`);
        throw new Error('Question not found');
      }

      console.log(`❓ GAME_SERVICE: Found question: "${question.text}", correct answer: ${question.correctAnswer}`);

      // Get current players to find the player
      const players = await dynamoService.getSessionPlayers(sessionId);
      const player = players.find(p => p.id === playerId);
      if (!player) {
        console.error(`❌ GAME_SERVICE: Player ${playerId} not found in session ${sessionId}`);
        throw new Error('Player not found');
      }

      console.log(`👤 GAME_SERVICE: Found player: ${player.name}, current score: ${player.score}`);

      // Check if player already answered this question
      const existingAnswer = player.answers.find(a => a.questionId === questionId);
      if (existingAnswer) {
        console.warn(`⚠️ GAME_SERVICE: Player ${playerId} already answered question ${questionId}`);
        throw new Error('Player already answered this question');
      }

      // Validate selected choice
      if (selectedChoice < 0 || selectedChoice >= question.choices.length) {
        console.error(`❌ GAME_SERVICE: Invalid choice ${selectedChoice} for question with ${question.choices.length} choices`);
        throw new Error('Invalid choice selected');
      }

      // Calculate points based on correctness and ranking
      const isCorrect = selectedChoice === question.correctAnswer;
      let points = 0;
      let rank = 0;
      let totalCorrect = 0;
      
      if (isCorrect) {
        // Get all correct answers for this question from all players
        const allPlayers = await dynamoService.getSessionPlayers(sessionId);
        const correctAnswersForQuestion = [];
        
        // Collect all correct answers for this question
        for (const p of allPlayers) {
          const correctAnswer = p.answers.find(a => 
            a.questionId === questionId && 
            a.isCorrect === true
          );
          if (correctAnswer) {
            correctAnswersForQuestion.push({
              playerId: p.id,
              playerName: p.name,
              submittedAt: new Date(correctAnswer.submittedAt || Date.now()),
              timeToAnswer: correctAnswer.timeToAnswer
            });
          }
        }
        
        // Add current answer to the list
        const currentSubmissionTime = new Date();
        correctAnswersForQuestion.push({
          playerId,
          playerName: player.name,
          submittedAt: currentSubmissionTime,
          timeToAnswer
        });
        
        // Sort by submission time (earliest first)
        correctAnswersForQuestion.sort((a, b) => a.submittedAt.getTime() - b.submittedAt.getTime());
        
        // Find current player's rank
        rank = correctAnswersForQuestion.findIndex(a => a.playerId === playerId) + 1;
        totalCorrect = correctAnswersForQuestion.length;
        
        // Dynamic scoring based on total participants
        const basePoints = question.points;
        
        if (totalCorrect === 1) {
          // Only one correct answer, give full points
          points = basePoints;
        } else {
          // Calculate percentage based on rank and total correct answers
          // Formula: 100% - ((rank - 1) / totalCorrect) * 50%
          // This ensures 1st place gets 100%, last place gets at least 50%
          const rankPercentage = 1.0 - ((rank - 1) / totalCorrect) * 0.5;
          points = Math.round(basePoints * rankPercentage);
          
          // Ensure minimum points (at least 30% of base points)
          const minPoints = Math.round(basePoints * 0.3);
          points = Math.max(points, minPoints);
        }
        
        console.log(`🏆 GAME_SERVICE: Correct answer! Rank: ${rank}/${totalCorrect}, Percentage: ${((points/basePoints)*100).toFixed(1)}%, Points: ${points}/${basePoints}`);
      } else {
        console.log(`❌ GAME_SERVICE: Wrong answer. Selected: ${selectedChoice}, Correct: ${question.correctAnswer}`);
      }

      // Create answer record
      const answer: PlayerAnswer = {
        questionId,
        selectedChoice,
        timeToAnswer,
        isCorrect,
        points,
        submittedAt: new Date().toISOString()
      };

      // Update player
      player.answers.push(answer);
      player.score += points;

      console.log(`💾 GAME_SERVICE: Updating player ${playerId} with new score: ${player.score}`);

      // Update player in DynamoDB
      await dynamoService.updatePlayer(sessionId, playerId, {
        score: player.score,
        answers: player.answers
      });

      console.log(`✅ GAME_SERVICE: Answer submitted successfully for player ${playerId}`);
      return { isCorrect, points, questionId, rank: isCorrect ? rank : undefined, totalCorrect: isCorrect ? totalCorrect : undefined };
    } catch (error) {
      console.error('❌ GAME_SERVICE: Error submitting answer:', error);
      return null;
    }
  }

  async getLeaderboard(sessionId: string): Promise<LeaderboardEntry[]> {
    try {
      const players = await dynamoService.getSessionPlayers(sessionId);

      // 리더보드용 플레이어 데이터 생성
      const leaderboardData = players.map((player) => {
        return {
          playerId: player.id,
          playerName: player.name,
          score: player.score
        };
      });

      // 점수 순으로 정렬하고 순위 할당
      leaderboardData.sort((a, b) => b.score - a.score);
      const rankedLeaderboard = leaderboardData.map((player, index) => ({
        ...player,
        rank: index + 1
      }));

      return rankedLeaderboard;
    } catch (error) {
      console.error('Error getting leaderboard:', error);
      return [];
    }
  }

  async finishGame(sessionId: string): Promise<boolean> {
    try {
      console.log(`🏁 GAME_SERVICE: Starting finishGame for session ${sessionId}`);
      
      // 세션 존재 여부 먼저 확인
      const existingSession = await dynamoService.getSession(sessionId);
      if (!existingSession) {
        console.error(`❌ GAME_SERVICE: Session ${sessionId} not found when finishing game`);
        return false;
      }
      
      console.log(`✅ GAME_SERVICE: Session ${sessionId} found, current status: ${existingSession.status}`);
      
      // 세션 상태를 finished로 업데이트
      console.log(`💾 GAME_SERVICE: Updating session ${sessionId} status to 'finished'`);
      const updateResult = await dynamoService.updateSession(sessionId, { 
        status: 'finished', 
        finishedAt: new Date().toISOString() 
      });
      
      if (!updateResult) {
        console.error(`❌ GAME_SERVICE: Failed to update session ${sessionId} status`);
        return false;
      }
      
      console.log(`✅ GAME_SERVICE: Session ${sessionId} status updated successfully`);

      // 게임 결과를 DynamoDB에 저장
      console.log(`📊 GAME_SERVICE: Starting to save game result for session ${sessionId}`);
      await this.saveGameResult(sessionId);
      console.log(`✅ GAME_SERVICE: Game result saving completed for session ${sessionId}`);

      console.log(`🎯 GAME_SERVICE: finishGame completed successfully for session ${sessionId}`);
      return true;
    } catch (error) {
      console.error(`❌ GAME_SERVICE: Error finishing game for session ${sessionId}:`, error);
      return false;
    }
  }

  private async saveGameResult(sessionId: string): Promise<void> {
    try {
      console.log(`📊 GAME_SERVICE: Saving game result for session ${sessionId}`);
      
      const session = await dynamoService.getSession(sessionId);
      if (!session) {
        console.error(`❌ GAME_SERVICE: Session ${sessionId} not found for result saving`);
        return;
      }

      const players = await dynamoService.getSessionPlayers(sessionId);
      const leaderboard = await this.getLeaderboard(sessionId);

      if (!session.quiz) {
        console.error(`❌ GAME_SERVICE: Quiz not found in session ${sessionId}`);
        return;
      }

      // 통계 계산
      const totalParticipants = players.length;
      const totalQuestions = session.quiz.questions.length;
      const averageScore = totalParticipants > 0 ? 
        Math.round(players.reduce((sum, player) => sum + player.score, 0) / totalParticipants) : 0;

      // 리더보드 변환
      const resultLeaderboard = leaderboard.map(entry => {
        return {
          rank: entry.rank,
          playerId: entry.playerId,
          playerName: entry.playerName,
          score: entry.score
        };
      });

      // 문제별 통계
      const questionStats = session.quiz.questions.map(question => {
        const questionAnswers = players.flatMap(player => 
          player.answers.filter(answer => answer.questionId === question.id)
        );
        
        const correctCount = questionAnswers.filter(answer => answer.isCorrect).length;
        const totalAnswers = questionAnswers.length;

        return {
          questionId: question.id,
          questionText: question.text,
          correctAnswer: question.correctAnswer,
          correctCount,
          totalAnswers
        };
      });

      // 게임 진행 시간 계산
      const duration = session.startedAt && session.finishedAt ? 
        Math.round((new Date(session.finishedAt).getTime() - new Date(session.startedAt).getTime()) / 1000) : 
        undefined;

      // GameResult 객체 생성
      const gameResult: GameResult = {
        sessionId,
        quizId: session.quizId,
        quizTitle: session.quiz.title,
        hostId: session.hostId,
        completedAt: new Date().toISOString(),
        totalParticipants,
        totalQuestions,
        averageScore,
        leaderboard: resultLeaderboard,
        questionStats,
        isPublic: true, // 기본적으로 공개 설정
        duration
      };

      // DynamoDB에 저장
      const saved = await dynamoService.saveGameResult(gameResult);
      
      if (saved) {
        console.log(`✅ GAME_SERVICE: Game result saved successfully for session ${sessionId}`);
      } else {
        console.error(`❌ GAME_SERVICE: Failed to save game result for session ${sessionId}`);
      }
    } catch (error) {
      console.error(`❌ GAME_SERVICE: Error saving game result for session ${sessionId}:`, error);
    }
  }

  async removePlayer(sessionId: string, playerId: string): Promise<boolean> {
    try {
      await dynamoService.removePlayer(sessionId, playerId);
      return true;
    } catch (error) {
      console.error('Error removing player:', error);
      return false;
    }
  }

  async getSessionByJoinCode(joinCode: string): Promise<GameSession | null> {
    try {
      const sessionId = await dynamoService.getSessionByJoinCode(joinCode);
      if (!sessionId) {
        return null;
      }

      const session = await dynamoService.getSession(sessionId);
      if (session) {
        // Load current players
        const players = await dynamoService.getSessionPlayers(sessionId);
        session.players = players;
      }

      return session;
    } catch (error) {
      console.error('Error getting session by join code:', error);
      return null;
    }
  }

  async getSessionData(sessionId: string): Promise<SessionData | null> {
    try {
      return await dynamoService.getSessionData(sessionId);
    } catch (error) {
      console.error('Error getting session data:', error);
      return null;
    }
  }

  async getSession(sessionId: string): Promise<GameSession | null> {
    try {
      const session = await dynamoService.getSession(sessionId);
      if (session) {
        // Load current players
        const players = await dynamoService.getSessionPlayers(sessionId);
        session.players = players;
      }
      return session;
    } catch (error) {
      console.error('Error getting session:', error);
      return null;
    }
  }

  async getSessionPlayers(sessionId: string): Promise<Player[]> {
    try {
      return await dynamoService.getSessionPlayers(sessionId);
    } catch (error) {
      console.error('Error getting session players:', error);
      return [];
    }
  }

  async getSessionResults(sessionId: string): Promise<{ leaderboard: LeaderboardEntry[]; sessionData: GameSession | null } | null> {
    try {
      console.log(`📊 GAME_SERVICE: Getting results for session ${sessionId}`);
      
      // 1. 먼저 저장된 게임 결과를 조회 (게임이 완료된 경우)
      console.log(`🎯 GAME_SERVICE: Checking for saved game result...`);
      const savedGameResult = await dynamoService.getGameResult(sessionId);
      
      if (savedGameResult) {
        console.log(`✅ GAME_SERVICE: Found saved game result for session ${sessionId}`);
        console.log(`📊 GAME_SERVICE: Game result info:`, {
          totalParticipants: savedGameResult.totalParticipants,
          totalQuestions: savedGameResult.totalQuestions,
          averageScore: savedGameResult.averageScore,
          leaderboardSize: savedGameResult.leaderboard.length
        });
        
        // 저장된 게임 결과를 변환하여 반환
        const leaderboard: LeaderboardEntry[] = savedGameResult.leaderboard.map(entry => ({
          playerId: entry.playerId,
          playerName: entry.playerName,
          score: entry.score,
          rank: entry.rank
        }));
        
        // 세션 정보도 함께 반환 (저장된 결과에서 재구성)
        const sessionData: GameSession = {
          id: sessionId,
          quizId: savedGameResult.quizId,
          hostId: savedGameResult.hostId,
          joinCode: 'FINISHED', // 게임 완료된 세션
          status: 'finished',
          currentQuestionIndex: savedGameResult.totalQuestions,
          players: savedGameResult.leaderboard.map(entry => ({
            id: entry.playerId,
            name: entry.playerName,
            sessionId,
            score: entry.score,
            answers: [], // 상세 답변 정보는 저장하지 않음
            isOnline: false,
            joinedAt: savedGameResult.completedAt
          })),
          createdAt: savedGameResult.completedAt,
          finishedAt: savedGameResult.completedAt,
          quiz: {
            id: savedGameResult.quizId,
            title: savedGameResult.quizTitle,
            description: '',
            creatorId: savedGameResult.hostId,
            questions: [], // 문제 정보는 별도 조회 필요
            createdAt: savedGameResult.completedAt,
            updatedAt: savedGameResult.completedAt
          }
        };
        
        return {
          leaderboard,
          sessionData
        };
      }
      
      console.log(`⚠️ GAME_SERVICE: No saved game result found, checking live session...`);
      
      // 2. 저장된 결과가 없으면 실시간 세션 데이터 조회
      const session = await dynamoService.getSession(sessionId);
      console.log(`🔍 GAME_SERVICE: Live session query result:`, session ? {
        id: session.id,
        status: session.status,
        hostId: session.hostId,
        joinCode: session.joinCode,
        hasQuiz: !!session.quiz,
        hasPlayers: !!session.players,
        createdAt: session.createdAt,
        finishedAt: session.finishedAt
      } : 'NULL');
      
      if (!session) {
        console.error(`❌ GAME_SERVICE: Session ${sessionId} not found in database`);
        console.log(`🚫 GAME_SERVICE: No session or game result found for ${sessionId}`);
        return null;
      }

      console.log(`✅ GAME_SERVICE: Found live session ${sessionId} with status: ${session.status}`);

      // 플레이어 데이터 로드
      console.log(`👥 GAME_SERVICE: Loading players for session ${sessionId}...`);
      const players = await dynamoService.getSessionPlayers(sessionId);
      session.players = players;
      
      console.log(`👥 GAME_SERVICE: Found ${players.length} players for session ${sessionId}`);
      if (players.length > 0) {
        console.log(`👥 GAME_SERVICE: Player sample:`, players.slice(0, 2).map(p => ({
          id: p.id,
          name: p.name,
          score: p.score,
          answersCount: p.answers?.length || 0
        })));
      }

      // 리더보드 생성
      console.log(`🏆 GAME_SERVICE: Generating leaderboard for session ${sessionId}...`);
      const leaderboard = await this.getLeaderboard(sessionId);
      
      console.log(`🏆 GAME_SERVICE: Generated leaderboard with ${leaderboard.length} entries`);
      if (leaderboard.length > 0) {
        console.log(`🏆 GAME_SERVICE: Leaderboard sample:`, leaderboard.slice(0, 3).map(entry => ({
          rank: entry.rank,
          playerName: entry.playerName,
          score: entry.score
        })));
      }
      
      console.log(`✅ GAME_SERVICE: Successfully retrieved live results for session ${sessionId}`);
      
      return {
        leaderboard,
        sessionData: session
      };
    } catch (error) {
      console.error(`❌ GAME_SERVICE: Error getting session results for ${sessionId}:`, error);
      console.error(`❌ GAME_SERVICE: Error stack:`, error instanceof Error ? error.stack : 'No stack trace');
      return null;
    }
  }
}

export default new GameService(); 