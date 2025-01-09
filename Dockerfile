FROM ruby:3.3.6-slim

# 安装系统依赖
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    default-libmysqlclient-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 复制Gemfile
COPY Gemfile Gemfile.lock ./

# 安装依赖
RUN bundle install

# 复制应用代码
COPY . .

# 暴露端口
EXPOSE 9292

# 启动命令
CMD ["bundle", "exec", "rackup", "-o", "0.0.0.0"]