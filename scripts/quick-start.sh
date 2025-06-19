#!/bin/bash

# DynSyn 快速启动脚本
# 用于云服务器快速部署和运行

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Docker 安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，正在安装..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        log_info "Docker 安装完成，请重新登录以使权限生效"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose 未安装，正在安装..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
}

# 检查 NVIDIA Docker（GPU 支持）
check_nvidia_docker() {
    if command -v nvidia-smi &> /dev/null; then
        log_info "检测到 NVIDIA GPU"
        if ! docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi &> /dev/null; then
            log_warn "NVIDIA Docker 运行时未正确配置，正在安装..."
            distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
            curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
            curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
            sudo apt-get update && sudo apt-get install -y nvidia-docker2
            sudo systemctl restart docker
        fi
    else
        log_warn "未检测到 NVIDIA GPU，将使用 CPU 模式"
    fi
}

# 构建镜像
build_image() {
    log_info "开始构建 DynSyn Docker 镜像..."
    docker-compose build --no-cache dynsyn
    log_info "镜像构建完成"
}

# 快速训练
quick_train() {
    local config_file=${1:-"configs/DynSyn/myowalk.json"}
    log_info "开始训练，使用配置: $config_file"
    
    docker-compose run --rm dynsyn \
        python -m dynsyn.sb3_runner.runner -f "$config_file"
}

# 生成 DynSyn 数据
generate_dynsyn() {
    local env_name=${1:-"myoLegWalk"}
    log_info "生成 DynSyn 数据，环境: $env_name"
    
    docker-compose run --rm dynsyn \
        python -m dynsyn.dynsyn -f configs/DynSynGen/dynsyn.yaml -e "$env_name"
}

# 启动开发环境
dev_env() {
    log_info "启动开发环境（包含 Jupyter Lab）"
    docker-compose --profile dev up -d
    log_info "Jupyter Lab 访问地址: http://localhost:8888"
    log_info "Token: dynsyn123"
}

# 清理环境
cleanup() {
    log_info "清理 Docker 环境..."
    docker-compose down -v --remove-orphans
    docker system prune -f
    log_info "清理完成"
}

# 显示帮助信息
show_help() {
    echo "DynSyn 快速启动脚本"
    echo ""
    echo "用法:"
    echo "  $0 [命令] [参数]"
    echo ""
    echo "命令:"
    echo "  setup           - 检查并安装必要的依赖"
    echo "  build           - 构建 Docker 镜像"
    echo "  train [config]  - 开始训练 (默认: configs/DynSyn/myowalk.json)"
    echo "  gen [env]       - 生成 DynSyn 数据 (默认: myoLegWalk)"
    echo "  dev             - 启动开发环境"
    echo "  clean           - 清理 Docker 环境"
    echo "  help            - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 setup"
    echo "  $0 build"
    echo "  $0 train configs/DynSyn/myowalk.json"
    echo "  $0 gen myoLegWalk"
    echo "  $0 dev"
}

# 主函数
main() {
    case "${1:-help}" in
        "setup")
            check_docker
            check_nvidia_docker
            log_info "环境检查完成"
            ;;
        "build")
            build_image
            ;;
        "train")
            quick_train "$2"
            ;;
        "gen")
            generate_dynsyn "$2"
            ;;
        "dev")
            dev_env
            ;;
        "clean")
            cleanup
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# 脚本入口
main "$@" 