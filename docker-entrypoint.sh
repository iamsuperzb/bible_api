#!/bin/bash
set -e

echo "Environment variables:"
echo "MYSQL_HOST: $MYSQL_HOST"
echo "DATABASE_URL: $DATABASE_URL"
echo "REDIS_URL: $REDIS_URL"

# 等待数据库准备就绪
echo "Waiting for MySQL..."
while ! nc -z $MYSQL_HOST 3306; do
  sleep 1
done
echo "MySQL started"

# 从DATABASE_URL中提取连接信息
DB_USER=$(echo $DATABASE_URL | sed -n 's/.*mysql2:\/\/\([^:]*\):.*/\1/p')
DB_PASS=$(echo $DATABASE_URL | sed -n 's/.*mysql2:\/\/[^:]*:\([^@]*\)@.*/\1/p')
DB_HOST=$(echo $DATABASE_URL | sed -n 's/.*@\([^:]*\):.*/\1/p')
DB_PORT=$(echo $DATABASE_URL | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')
DB_NAME=$(echo $DATABASE_URL | sed -n 's/.*\/\([^?]*\).*/\1/p')

echo "Database connection info:"
echo "User: $DB_USER"
echo "Database: $DB_NAME"
echo "Host: $DB_HOST"
echo "Port: $DB_PORT"

# 检查圣经数据
echo "Checking Bible data..."
ls -la bibles/

# 初始化数据库
echo "Importing Bible translations..."
MYSQL_PWD=$DB_PASS bundle exec ruby import.rb

echo "Starting application..."
exec "$@" 