import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, PutCommand, UpdateCommand, DeleteCommand, QueryCommand, BatchWriteCommand, ScanCommand } from '@aws-sdk/lib-dynamodb';
import { Quiz, GameSession, Player, PlayerAnswer, SessionData } from '../types';
import { demoQuiz, isDemoQuiz } from '../demoData';

// GameResult interface - 별도로 정의
interface GameResult {
  sessionId: string;
  quizId: string;
  quizTitle: string;
  hostId: string;
  completedAt: string;
  totalParticipants: number;
  totalQuestions: number;
  averageScore: number;
  leaderboard: Array<{
    rank: number;
    playerId: string;
    playerName: string;
    score: number;
  }>;
  questionStats: Array<{
    questionId: string;
    questionText: string;
    correctAnswer: number;
    correctCount: number;
    totalAnswers: number;
  }>;
  isPublic?: boolean;
  duration?: number;
}

class DynamoDBService {
  private client: DynamoDBDocumentClient;
  private tableName: string;

  constructor() {
    // Use EC2 IAM credentials - no need for explicit credentials
    const dynamoClient = new DynamoDBClient({
      region: process.env.AWS_REGION || 'ap-northeast-2',
    });
    
    this.client = DynamoDBDocumentClient.from(dynamoClient);
    this.tableName = process.env.DYNAMODB_TABLE || 'amahoot-game-data';
  }

  // Quiz operations
  async saveQuiz(quiz: Quiz): Promise<boolean> {
    try {
      const command = new PutCommand({
        TableName: this.tableName,
        Item: {
          pk: `QUIZ#${quiz.id}`,
          sk: 'METADATA',
          ...quiz,
          ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours TTL
        }
      });
      
      await this.client.send(command);
      return true;
    } catch (error) {
      console.error('Error saving quiz:', error);
      return false;
    }
  }

  async getQuiz(quizId: string): Promise<Quiz | null> {
    try {
      console.log(`🔍 DYNAMODB: getQuiz called with quizId: ${quizId}`);
      
      // Return demo quiz if it's the demo quiz ID
      if (isDemoQuiz(quizId)) {
        console.log('📚 DYNAMODB: Returning demo quiz data');
        return demoQuiz;
      }

      console.log(`📤 DYNAMODB: Sending GetCommand to DynamoDB for quiz ${quizId}...`);
      const command = new GetCommand({
        TableName: this.tableName,
        Key: { 
          pk: `QUIZ#${quizId}`,
          sk: 'METADATA'
        }
      });
      
      console.log(`📤 DYNAMODB: GetCommand details:`, {
        TableName: this.tableName,
        Key: { pk: `QUIZ#${quizId}`, sk: 'METADATA' }
      });
      
      const result = await this.client.send(command);
      console.log(`📥 DYNAMODB: GetCommand result:`, {
        hasItem: !!result.Item,
        itemKeys: result.Item ? Object.keys(result.Item) : 'none'
      });
      
      if (!result.Item) {
        console.log(`❌ DYNAMODB: Quiz ${quizId} not found in DynamoDB`);
        return null;
      }

      const { pk, sk, ttl, ...quiz } = result.Item;
      console.log(`✅ DYNAMODB: Quiz ${quizId} retrieved successfully:`, {
        id: (quiz as Quiz).id,
        title: (quiz as Quiz).title,
        questionsCount: (quiz as Quiz).questions?.length || 0
      });
      
      return quiz as Quiz;
    } catch (error) {
      console.error(`❌ DYNAMODB: Error getting quiz ${quizId}:`, error);
      console.error(`❌ DYNAMODB: Error stack:`, error instanceof Error ? error.stack : 'No stack trace');
      return null;
    }
  }

  // Session operations
  async saveSession(session: GameSession): Promise<boolean> {
    try {
      const command = new PutCommand({
        TableName: this.tableName,
        Item: {
          pk: `SESSION#${session.id}`,
          sk: 'METADATA',
          ...session,
          ttl: Math.floor(Date.now() / 1000) + (12 * 60 * 60) // 12 hours TTL
        }
      });
      
      await this.client.send(command);
      return true;
    } catch (error) {
      console.error('Error saving session:', error);
      return false;
    }
  }

  async getSession(sessionId: string): Promise<GameSession | null> {
    try {
      console.log(`🔍 DYNAMODB: Getting session ${sessionId} from DynamoDB...`);
      
      const command = new GetCommand({
        TableName: this.tableName,
        Key: { 
          pk: `SESSION#${sessionId}`,
          sk: 'METADATA'
        }
      });
      
      console.log(`📤 DYNAMODB: Sending GetCommand for pk: SESSION#${sessionId}, sk: METADATA`);
      const result = await this.client.send(command);
      console.log(`📥 DYNAMODB: GetCommand result:`, {
        hasItem: !!result.Item,
        itemKeys: result.Item ? Object.keys(result.Item) : 'none'
      });
      
      if (!result.Item) {
        console.log(`❌ DYNAMODB: No item found for session ${sessionId}`);
        return null;
      }

      const { pk, sk, ttl, ...sessionData } = result.Item;
      const session = sessionData as GameSession;
      
      console.log(`✅ DYNAMODB: Session ${sessionId} retrieved successfully:`, {
        id: session.id,
        status: session.status,
        hostId: session.hostId,
        joinCode: session.joinCode,
        hasQuiz: !!session.quiz
      });

      return session;
    } catch (error) {
      console.error(`❌ DYNAMODB: Error getting session ${sessionId}:`, error);
      console.error(`❌ DYNAMODB: Error stack:`, error instanceof Error ? error.stack : 'No stack trace');
      return null;
    }
  }

  async updateSession(sessionId: string, updates: Partial<GameSession>): Promise<boolean> {
    try {
      const updateExpression = [];
      const expressionAttributeNames: any = {};
      const expressionAttributeValues: any = {};
      
      for (const [key, value] of Object.entries(updates)) {
        updateExpression.push(`#${key} = :${key}`);
        expressionAttributeNames[`#${key}`] = key;
        expressionAttributeValues[`:${key}`] = value;
      }
      
      const command = new UpdateCommand({
        TableName: this.tableName,
        Key: { 
          pk: `SESSION#${sessionId}`,
          sk: 'METADATA'
        },
        UpdateExpression: `SET ${updateExpression.join(', ')}`,
        ExpressionAttributeNames: expressionAttributeNames,
        ExpressionAttributeValues: expressionAttributeValues
      });
      
      await this.client.send(command);
      return true;
    } catch (error) {
      console.error('Error updating session:', error);
      return false;
    }
  }

  // Player operations
  async savePlayer(sessionId: string, player: Player): Promise<boolean> {
    try {
      const command = new PutCommand({
        TableName: this.tableName,
        Item: {
          pk: `SESSION#${sessionId}`,
          sk: `PLAYER#${player.id}`,
          ...player,
          ttl: Math.floor(Date.now() / 1000) + (12 * 60 * 60) // 12 hours TTL
        }
      });
      
      await this.client.send(command);
      return true;
    } catch (error) {
      console.error('Error saving player:', error);
      return false;
    }
  }

  async getSessionPlayers(sessionId: string): Promise<Player[]> {
    try {
      const command = new QueryCommand({
        TableName: this.tableName,
        KeyConditionExpression: 'pk = :pk AND begins_with(sk, :sk)',
        ExpressionAttributeValues: {
          ':pk': `SESSION#${sessionId}`,
          ':sk': 'PLAYER#'
        }
      });
      
      const result = await this.client.send(command);
      if (!result.Items) return [];

      return result.Items.map(item => {
        const { pk, sk, ttl, ...player } = item;
        return player as Player;
      });
    } catch (error) {
      console.error('Error getting session players:', error);
      return [];
    }
  }

  async updatePlayer(sessionId: string, playerId: string, updates: Partial<Player>): Promise<boolean> {
    try {
      const updateExpression = [];
      const expressionAttributeNames: any = {};
      const expressionAttributeValues: any = {};
      
      for (const [key, value] of Object.entries(updates)) {
        updateExpression.push(`#${key} = :${key}`);
        expressionAttributeNames[`#${key}`] = key;
        expressionAttributeValues[`:${key}`] = value;
      }
      
      const command = new UpdateCommand({
        TableName: this.tableName,
        Key: { 
          pk: `SESSION#${sessionId}`,
          sk: `PLAYER#${playerId}`
        },
        UpdateExpression: `SET ${updateExpression.join(', ')}`,
        ExpressionAttributeNames: expressionAttributeNames,
        ExpressionAttributeValues: expressionAttributeValues
      });
      
      await this.client.send(command);
      return true;
    } catch (error) {
      console.error('Error updating player:', error);
      return false;
    }
  }

  async removePlayer(sessionId: string, playerId: string): Promise<boolean> {
    try {
      const command = new DeleteCommand({
        TableName: this.tableName,
        Key: { 
          pk: `SESSION#${sessionId}`,
          sk: `PLAYER#${playerId}`
        }
      });
      
      await this.client.send(command);
      return true;
    } catch (error) {
      console.error('Error removing player:', error);
      return false;
    }
  }

  // Join code operations
  async setJoinCode(joinCode: string, sessionId: string): Promise<boolean> {
    try {
      const command = new PutCommand({
        TableName: this.tableName,
        Item: {
          pk: `JOINCODE#${joinCode}`,
          sk: 'SESSION',
          sessionId,
          ttl: Math.floor(Date.now() / 1000) + (12 * 60 * 60) // 12 hours TTL
        }
      });
      
      await this.client.send(command);
      return true;
    } catch (error) {
      console.error('Error setting join code:', error);
      return false;
    }
  }

  async getSessionByJoinCode(joinCode: string): Promise<string | null> {
    try {
      const command = new GetCommand({
        TableName: this.tableName,
        Key: { 
          pk: `JOINCODE#${joinCode}`,
          sk: 'SESSION'
        }
      });
      
      const result = await this.client.send(command);
      return result.Item?.sessionId || null;
    } catch (error) {
      console.error('Error getting session by join code:', error);
      return null;
    }
  }

  // Socket management
  async setHostSocket(sessionId: string, socketId: string): Promise<boolean> {
    try {
      const command = new PutCommand({
        TableName: this.tableName,
        Item: {
          pk: `SESSION#${sessionId}`,
          sk: 'HOST_SOCKET',
          socketId,
          ttl: Math.floor(Date.now() / 1000) + (6 * 60 * 60) // 6 hours TTL
        }
      });
      
      await this.client.send(command);
      return true;
    } catch (error) {
      console.error('Error setting host socket:', error);
      return false;
    }
  }

  async getHostSocket(sessionId: string): Promise<string | null> {
    try {
      const command = new GetCommand({
        TableName: this.tableName,
        Key: { 
          pk: `SESSION#${sessionId}`,
          sk: 'HOST_SOCKET'
        }
      });
      
      const result = await this.client.send(command);
      return result.Item?.socketId || null;
    } catch (error) {
      console.error('Error getting host socket:', error);
      return null;
    }
  }

  async setPlayerSocket(sessionId: string, playerId: string, socketId: string): Promise<boolean> {
    try {
      const command = new PutCommand({
        TableName: this.tableName,
        Item: {
          pk: `SESSION#${sessionId}`,
          sk: `SOCKET#${playerId}`,
          socketId,
          playerId,
          ttl: Math.floor(Date.now() / 1000) + (6 * 60 * 60) // 6 hours TTL
        }
      });
      
      await this.client.send(command);
      return true;
    } catch (error) {
      console.error('Error setting player socket:', error);
      return false;
    }
  }

  async getPlayerSocket(sessionId: string, playerId: string): Promise<string | null> {
    try {
      const command = new GetCommand({
        TableName: this.tableName,
        Key: { 
          pk: `SESSION#${sessionId}`,
          sk: `SOCKET#${playerId}`
        }
      });
      
      const result = await this.client.send(command);
      return result.Item?.socketId || null;
    } catch (error) {
      console.error('Error getting player socket:', error);
      return null;
    }
  }

  async getAllPlayerSockets(sessionId: string): Promise<{ [playerId: string]: string }> {
    try {
      const command = new QueryCommand({
        TableName: this.tableName,
        KeyConditionExpression: 'pk = :pk AND begins_with(sk, :sk)',
        ExpressionAttributeValues: {
          ':pk': `SESSION#${sessionId}`,
          ':sk': 'SOCKET#'
        }
      });
      
      const result = await this.client.send(command);
      if (!result.Items) return {};

      const socketMap: { [playerId: string]: string } = {};
      result.Items.forEach(item => {
        if (item.playerId && item.socketId) {
          socketMap[item.playerId] = item.socketId;
        }
      });

      return socketMap;
    } catch (error) {
      console.error('Error getting all player sockets:', error);
      return {};
    }
  }

  async removeSocket(sessionId: string, socketId: string): Promise<boolean> {
    try {
      // Remove host socket if it matches
      const hostSocket = await this.getHostSocket(sessionId);
      if (hostSocket === socketId) {
        await this.client.send(new DeleteCommand({
          TableName: this.tableName,
          Key: { 
            pk: `SESSION#${sessionId}`,
            sk: 'HOST_SOCKET'
          }
        }));
      }

      // Find and remove player socket
      const playerSockets = await this.getAllPlayerSockets(sessionId);
      for (const [playerId, playerSocketId] of Object.entries(playerSockets)) {
        if (playerSocketId === socketId) {
          await this.client.send(new DeleteCommand({
            TableName: this.tableName,
            Key: { 
              pk: `SESSION#${sessionId}`,
              sk: `SOCKET#${playerId}`
            }
          }));
          break;
        }
      }

      return true;
    } catch (error) {
      console.error('Error removing socket:', error);
      return false;
    }
  }

  // Cleanup operations
  async deleteSession(sessionId: string): Promise<boolean> {
    try {
      // Get all items for this session
      const command = new QueryCommand({
        TableName: this.tableName,
        KeyConditionExpression: 'pk = :pk',
        ExpressionAttributeValues: {
          ':pk': `SESSION#${sessionId}`
        }
      });
      
      const result = await this.client.send(command);
      if (!result.Items || result.Items.length === 0) return true;

      // Batch delete all session-related items
      const deleteRequests = result.Items.map(item => ({
        DeleteRequest: {
          Key: { pk: item.pk, sk: item.sk }
        }
      }));

      // DynamoDB batch write supports max 25 items
      const batchSize = 25;
      for (let i = 0; i < deleteRequests.length; i += batchSize) {
        const batch = deleteRequests.slice(i, i + batchSize);
        await this.client.send(new BatchWriteCommand({
          RequestItems: {
            [this.tableName]: batch
          }
        }));
      }

      return true;
    } catch (error) {
      console.error('Error deleting session:', error);
      return false;
    }
  }

  // Session data operations (for backward compatibility)
  async getSessionData(sessionId: string): Promise<SessionData | null> {
    try {
      const session = await this.getSession(sessionId);
      if (!session) return null;

      const players = await this.getSessionPlayers(sessionId);
      const hostSocketId = await this.getHostSocket(sessionId);
      const playerSocketIds = await this.getAllPlayerSockets(sessionId);

      // Update session with current players
      session.players = players;

      return {
        session,
        hostSocketId: hostSocketId || undefined,
        playerSocketIds
      };
    } catch (error) {
      console.error('Error getting session data:', error);
      return null;
    }
  }

  // Game Results operations
  async saveGameResult(gameResult: GameResult): Promise<boolean> {
    try {
      console.log(`💾 DYNAMODB: Saving game result for session ${gameResult.sessionId}`);
      
      const command = new PutCommand({
        TableName: this.tableName,
        Item: {
          pk: `GAME_RESULT#${gameResult.sessionId}`,
          sk: 'METADATA',
          ...gameResult,
          ttl: Math.floor(Date.now() / 1000) + (365 * 24 * 60 * 60) // 1년 후 만료
        }
      });

      await this.client.send(command);
      console.log(`✅ DYNAMODB: Game result saved successfully for session ${gameResult.sessionId}`);
      return true;
    } catch (error) {
      console.error('Error saving game result:', error);
      return false;
    }
  }

  async getGameResult(sessionId: string): Promise<GameResult | null> {
    try {
      console.log(`🔍 DYNAMODB: Getting game result for session ${sessionId}`);
      
      const command = new GetCommand({
        TableName: this.tableName,
        Key: { 
          pk: `GAME_RESULT#${sessionId}`,
          sk: 'METADATA'
        }
      });
      
      console.log(`📤 DYNAMODB: Querying for game result with pk: GAME_RESULT#${sessionId}, sk: METADATA`);
      const result = await this.client.send(command);
      console.log(`📥 DYNAMODB: Game result query result:`, {
        hasItem: !!result.Item,
        itemKeys: result.Item ? Object.keys(result.Item) : 'none'
      });
      
      if (!result.Item) {
        console.log(`❌ DYNAMODB: No game result found for session ${sessionId}`);
        return null;
      }

      const { pk, sk, ttl, ...gameResult } = result.Item;
      const finalResult = gameResult as GameResult;
      
      console.log(`✅ DYNAMODB: Found game result for session ${sessionId}:`, {
        sessionId: finalResult.sessionId,
        quizId: finalResult.quizId,
        quizTitle: finalResult.quizTitle,
        totalParticipants: finalResult.totalParticipants,
        leaderboardSize: finalResult.leaderboard?.length || 0,
        completedAt: finalResult.completedAt
      });
      
      return finalResult;
    } catch (error) {
      console.error('❌ DYNAMODB: Error getting game result:', error);
      return null;
    }
  }

  async getRecentGameResults(limit: number = 20): Promise<GameResult[]> {
    try {
      console.log(`📊 DYNAMODB: Getting recent game results (limit: ${limit})`);
      
      const command = new QueryCommand({
        TableName: this.tableName,
        IndexName: 'GSI1', // Global Secondary Index needed for this query
        KeyConditionExpression: 'gsi1pk = :gsi1pk',
        ExpressionAttributeValues: {
          ':gsi1pk': 'GAME_RESULT'
        },
        ScanIndexForward: false, // 최신순으로 정렬
        Limit: limit
      });

      const result = await this.client.send(command);
      const gameResults = (result.Items || []).map(item => {
        const { pk, sk, ttl, gsi1pk, gsi1sk, ...gameResult } = item;
        return gameResult as GameResult;
      });

      console.log(`✅ DYNAMODB: Retrieved ${gameResults.length} game results`);
      return gameResults;
    } catch (error) {
      console.error('Error getting recent game results:', error);
      return [];
    }
  }

  async getPublicGameResults(quizTitle?: string, limit: number = 50): Promise<GameResult[]> {
    try {
      console.log(`🌐 DYNAMODB: Getting public game results (quiz: ${quizTitle || 'all'}, limit: ${limit})`);
      
      // 퀴즈별 필터가 있는 경우
      if (quizTitle) {
        const command = new ScanCommand({
          TableName: this.tableName,
          FilterExpression: 'begins_with(pk, :pk_prefix) AND quizTitle = :quizTitle AND isPublic = :isPublic',
          ExpressionAttributeValues: {
            ':pk_prefix': 'GAME_RESULT#',
            ':quizTitle': quizTitle,
            ':isPublic': true
          },
          Limit: limit
        });

        const result = await this.client.send(command);
        return (result.Items || []).map((item: any) => {
          const { pk, sk, ttl, ...gameResult } = item;
          return gameResult as GameResult;
        });
      } else {
        // 전체 공개 게임 결과 조회
        const command = new ScanCommand({
          TableName: this.tableName,
          FilterExpression: 'begins_with(pk, :pk_prefix) AND isPublic = :isPublic',
          ExpressionAttributeValues: {
            ':pk_prefix': 'GAME_RESULT#',
            ':isPublic': true
          },
          Limit: limit
        });

        const result = await this.client.send(command);
        const gameResults = (result.Items || []).map((item: any) => {
          const { pk, sk, ttl, ...gameResult } = item;
          return gameResult as GameResult;
        });

        // 완료 시간으로 정렬 (최신순)
        gameResults.sort((a: GameResult, b: GameResult) => new Date(b.completedAt).getTime() - new Date(a.completedAt).getTime());
        
        console.log(`✅ DYNAMODB: Retrieved ${gameResults.length} public game results`);
        return gameResults;
      }
    } catch (error) {
      console.error('Error getting public game results:', error);
      return [];
    }
  }

  async getGameResultsByQuiz(quizId: string, limit: number = 20): Promise<GameResult[]> {
    try {
      console.log(`📊 DYNAMODB: Getting game results for quiz ${quizId} (limit: ${limit})`);
      
      const command = new ScanCommand({
        TableName: this.tableName,
        FilterExpression: 'begins_with(pk, :pk_prefix) AND quizId = :quizId',
        ExpressionAttributeValues: {
          ':pk_prefix': 'GAME_RESULT#',
          ':quizId': quizId
        },
        Limit: limit
      });

      const result = await this.client.send(command);
      console.log(`📥 DYNAMODB: Raw scan result for quiz ${quizId}:`, {
        hasItems: !!result.Items,
        itemCount: result.Items?.length || 0
      });
      
      const gameResults = (result.Items || []).map((item: any) => {
        const { pk, sk, ttl, averageAccuracy, ...gameResult } = item;
        
        // 리더보드에서 정확도 필드 제거
        if (gameResult.leaderboard) {
          gameResult.leaderboard = gameResult.leaderboard.map((entry: any) => {
            const { accuracy, ...cleanEntry } = entry;
            return cleanEntry;
          });
        }
        
        // 문제 통계에서 정확도 필드 제거  
        if (gameResult.questionStats) {
          gameResult.questionStats = gameResult.questionStats.map((stat: any) => {
            const { accuracyRate, ...cleanStat } = stat;
            return cleanStat;
          });
        }
        
        return gameResult as GameResult;
      });

      // 완료 시간으로 정렬 (최신순)
      gameResults.sort((a: GameResult, b: GameResult) => new Date(b.completedAt).getTime() - new Date(a.completedAt).getTime());
      
      console.log(`✅ DYNAMODB: Retrieved ${gameResults.length} game results for quiz ${quizId}`);
      if (gameResults.length > 0) {
        console.log(`📋 DYNAMODB: Sample result:`, {
          sessionId: gameResults[0].sessionId,
          completedAt: gameResults[0].completedAt,
          totalParticipants: gameResults[0].totalParticipants,
          leaderboardSize: gameResults[0].leaderboard?.length || 0
        });
      }
      
      return gameResults;
    } catch (error) {
      console.error('Error getting game results by quiz:', error);
      return [];
    }
  }
}

export default new DynamoDBService(); 