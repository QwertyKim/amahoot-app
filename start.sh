#!/bin/bash

# Amahoot WebSocket Server 시작 스크립트
echo "🚀 Amahoot WebSocket Server 시작 중..."

# 환경변수 설정
export PORT=5000
export CORS_ORIGIN=http://localhost:3000
export AWS_REGION=us-east-1
export DYNAMODB_TABLE=amahoot-game-data

echo "포트: $PORT"
echo "CORS 허용: $CORS_ORIGIN"
echo "AWS 리전: $AWS_REGION"
echo "DynamoDB 테이블: $DYNAMODB_TABLE"
echo ""

# 서버 시작
npm start 