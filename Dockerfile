# 多阶段构建 - 基础环境
FROM python:3.9-slim as base

# 设置环境变量
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    POETRY_NO_INTERACTION=1 \
    POETRY_VENV_IN_PROJECT=1 \
    POETRY_CACHE_DIR=/opt/poetry-cache \
    POETRY_HOME="/opt/poetry" \
    POETRY_VERSION=1.7.1

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    curl \
    wget \
    unzip \
    libosmesa6-dev \
    libgl1-mesa-glx \
    libglfw3 \
    libglfw3-dev \
    xvfb \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# 安装 Poetry
RUN pip install poetry==$POETRY_VERSION

# 依赖安装阶段
FROM base as deps

WORKDIR /app
COPY pyproject.toml poetry.lock ./

# 配置 Poetry 并安装依赖
RUN poetry config virtualenvs.create false \
    && poetry install --no-dev --no-root \
    && rm -rf $POETRY_CACHE_DIR

# 生产环境
FROM base as production

# 创建非 root 用户
RUN useradd --create-home --shell /bin/bash app

# 从依赖阶段复制已安装的包
COPY --from=deps /usr/local/lib/python3.9/site-packages /usr/local/lib/python3.9/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin

# 设置工作目录
WORKDIR /app

# 复制应用代码
COPY . .

# 设置权限
RUN chown -R app:app /app
USER app

# 设置 MuJoCo 渲染环境
ENV MUJOCO_GL=egl
ENV DISPLAY=:0

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import dynsyn; print('OK')" || exit 1

# 暴露端口（如果有 web 界面或 API）
EXPOSE 8000

# 默认命令
CMD ["python", "-m", "dynsyn.sb3_runner.runner", "--help"] 