# Multi-stage build - Base environment
FROM python:3.9-slim as base

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    POETRY_NO_INTERACTION=1 \
    POETRY_VENV_IN_PROJECT=1 \
    POETRY_CACHE_DIR=/opt/poetry-cache \
    POETRY_HOME="/opt/poetry" \
    POETRY_VERSION=1.7.1

# Install system dependencies
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

# Install Poetry
RUN pip install poetry==$POETRY_VERSION

# Dependency installation stage
FROM base as deps

WORKDIR /app
COPY pyproject.toml poetry.lock ./

# Configure Poetry and install dependencies
RUN poetry config virtualenvs.create false \
    && poetry install --no-dev --no-root \
    && rm -rf $POETRY_CACHE_DIR

# Production environment
FROM base as production

# Create non-root user
RUN useradd --create-home --shell /bin/bash app

# Copy installed packages from dependency stage
COPY --from=deps /usr/local/lib/python3.9/site-packages /usr/local/lib/python3.9/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin

# Set working directory
WORKDIR /app

# Copy application code
COPY . .

# Set permissions
RUN chown -R app:app /app
USER app

# Set MuJoCo rendering environment
ENV MUJOCO_GL=egl
ENV DISPLAY=:0

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import dynsyn; print('OK')" || exit 1

# Expose ports (if there's a web interface or API)
EXPOSE 8000

# Default command
CMD ["python", "-m", "dynsyn.sb3_runner.runner", "--help"] 