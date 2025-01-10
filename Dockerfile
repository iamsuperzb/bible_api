FROM ruby:3.2.2-slim

# 安装系统依赖
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    default-libmysqlclient-dev \
    default-mysql-client \
    git \
    netcat-traditional \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 复制应用代码
COPY . .

# 安装依赖
COPY Gemfile ./
RUN rm -f Gemfile.lock && \
    bundle install && \
    bundle lock

# 添加启动脚本权限
RUN chmod +x docker-entrypoint.sh

# 暴露端口
EXPOSE 9292

# 设置启动脚本
ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["bundle", "exec", "rackup", "-o", "0.0.0.0"]