#!/bin/bash
set -e

# 等待数据库准备就绪
echo "Waiting for MySQL..."
while ! nc -z $MYSQL_HOST 3306; do
  sleep 1
done
echo "MySQL started"

# 从DATABASE_URL中提取用户名和密码
DB_USER=$(echo $DATABASE_URL | sed -n 's/.*mysql2:\/\/\([^:]*\):.*/\1/p')
DB_PASS=$(echo $DATABASE_URL | sed -n 's/.*mysql2:\/\/[^:]*:\([^@]*\)@.*/\1/p')
DB_NAME=$(echo $DATABASE_URL | sed -n 's/.*\/\([^?]*\).*/\1/p')

echo "Creating database if not exists..."
mysql -h"$MYSQL_HOST" -u"$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"

# 检查数据库是否已经有数据
echo "Checking if database is already initialized..."
TABLES=$(mysql -h"$MYSQL_HOST" -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -N -e "show tables;" 2>/dev/null || echo "")

if [ -z "$TABLES" ]; then
    echo "Database is empty, importing Bible translations..."
    # 尝试导入，最多重试3次
    for i in {1..3}; do
        if bundle exec ruby import.rb; then
            echo "Import successful!"
            break
        else
            echo "Import attempt $i failed, retrying..."
            sleep 5
        fi
    done
else
    echo "Database already contains tables, skipping import..."
fi

# 启动应用
exec "$@" 