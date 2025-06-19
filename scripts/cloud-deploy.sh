#!/bin/bash

# DynSyn 云服务器一键部署脚本
# 适用于全新的云服务器实例，一条命令完成所有部署

set -e

# 配置参数
DOCKER_IMAGE="dynsyn/dynsyn:latest"
PROJECT_DIR="/opt/dynsyn"
CONFIG_FILE="configs/DynSyn/myowalk.json"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 检测操作系统
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        log_error "无法检测操作系统"
        exit 1
    fi
    log_info "检测到操作系统: $OS $VERSION"
}

# 更新系统
update_system() {
    log_step "更新系统包..."
    if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        sudo apt-get update -y
        sudo apt-get install -y curl wget git htop
    elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "fedora" ]]; then
        sudo yum update -y
        sudo yum install -y curl wget git htop
    else
        log_warn "未知的操作系统，跳过系统更新"
    fi
}

# 安装 Docker
install_docker() {
    if command -v docker &> /dev/null; then
        log_info "Docker 已安装: $(docker --version)"
        return
    fi
    
    log_step "安装 Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    
    # 启动 Docker 服务
    sudo systemctl enable docker
    sudo systemctl start docker
    
    log_info "Docker 安装完成"
}

# 安装 Docker Compose
install_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        log_info "Docker Compose 已安装: $(docker-compose --version)"
        return
    fi
    
    log_step "安装 Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    log_info "Docker Compose 安装完成"
}

# 安装 NVIDIA Docker (如果有 GPU)
install_nvidia_docker() {
    if ! command -v nvidia-smi &> /dev/null; then
        log_info "未检测到 NVIDIA GPU，跳过 NVIDIA Docker 安装"
        return
    fi
    
    log_step "安装 NVIDIA Docker..."
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    
    if [[ "$OS" == "ubuntu" ]]; then
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
        sudo apt-get update
        sudo apt-get install -y nvidia-docker2
    elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]]; then
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo | sudo tee /etc/yum.repos.d/nvidia-docker.repo
        sudo yum install -y nvidia-docker2
    fi
    
    sudo systemctl restart docker
    log_info "NVIDIA Docker 安装完成"
}

# 拉取 Docker 镜像
pull_docker_image() {
    log_step "拉取 DynSyn Docker 镜像..."
    sudo docker pull $DOCKER_IMAGE
    log_info "Docker 镜像拉取完成"
}

# 创建项目目录和配置
setup_project() {
    log_step "设置项目目录..."
    
    sudo mkdir -p $PROJECT_DIR
    sudo chown -R $USER:$USER $PROJECT_DIR
    cd $PROJECT_DIR
    
    # 克隆配置文件（如果需要）
    if [[ ! -d "configs" ]]; then
        log_info "下载项目配置文件..."
        git clone --depth 1 https://github.com/ShanningZhuang/DynSyn_Kaibo.git temp_repo
        cp -r temp_repo/configs .
        rm -rf temp_repo
    fi
    
    # 创建必要的目录
    mkdir -p logs results data
    
    log_info "项目目录设置完成: $PROJECT_DIR"
}

# 创建运行脚本
create_run_script() {
    log_step "创建运行脚本..."
    
    cat > $PROJECT_DIR/run_training.sh << 'EOF'
#!/bin/bash

# DynSyn 训练运行脚本

CONFIG_FILE=${1:-"configs/DynSyn/myowalk.json"}
DOCKER_IMAGE="dynsyn/dynsyn:latest"

echo "开始 DynSyn 训练..."
echo "配置文件: $CONFIG_FILE"
echo "Docker 镜像: $DOCKER_IMAGE"

# 检查 GPU
if command -v nvidia-smi &> /dev/null; then
    echo "检测到 NVIDIA GPU，使用 GPU 模式"
    GPU_FLAG="--gpus all"
else
    echo "未检测到 GPU，使用 CPU 模式"
    GPU_FLAG=""
fi

# 运行训练
docker run --rm -it \
    $GPU_FLAG \
    -v $(pwd)/configs:/app/configs \
    -v $(pwd)/logs:/app/logs \
    -v $(pwd)/results:/app/results \
    -e MUJOCO_GL=egl \
    -e WANDB_API_KEY=${WANDB_API_KEY:-""} \
    $DOCKER_IMAGE \
    python -m dynsyn.sb3_runner.runner -f "$CONFIG_FILE"

echo "训练完成！"
echo "日志保存在: $(pwd)/logs"
echo "结果保存在: $(pwd)/results"
EOF

    chmod +x $PROJECT_DIR/run_training.sh
    log_info "运行脚本创建完成: $PROJECT_DIR/run_training.sh"
}

# 创建 DynSyn 数据生成脚本
create_dynsyn_script() {
    log_step "创建 DynSyn 数据生成脚本..."
    
    cat > $PROJECT_DIR/generate_dynsyn.sh << 'EOF'
#!/bin/bash

# DynSyn 数据生成脚本

ENV_NAME=${1:-"myoLegWalk"}
DOCKER_IMAGE="dynsyn/dynsyn:latest"

echo "生成 DynSyn 数据..."
echo "环境: $ENV_NAME"

# 检查 GPU
if command -v nvidia-smi &> /dev/null; then
    GPU_FLAG="--gpus all"
else
    GPU_FLAG=""
fi

# 生成数据
docker run --rm -it \
    $GPU_FLAG \
    -v $(pwd)/configs:/app/configs \
    -v $(pwd)/logs:/app/logs \
    -v $(pwd)/data:/app/data \
    -e MUJOCO_GL=egl \
    $DOCKER_IMAGE \
    python -m dynsyn.dynsyn -f configs/DynSynGen/dynsyn.yaml -e "$ENV_NAME"

echo "DynSyn 数据生成完成！"
EOF

    chmod +x $PROJECT_DIR/generate_dynsyn.sh
    log_info "DynSyn 数据生成脚本创建完成: $PROJECT_DIR/generate_dynsyn.sh"
}

# 创建监控脚本
create_monitor_script() {
    log_step "创建系统监控脚本..."
    
    cat > $PROJECT_DIR/monitor.sh << 'EOF'
#!/bin/bash

# 系统监控脚本

echo "=== DynSyn 系统监控 ==="
echo "时间: $(date)"
echo ""

echo "=== Docker 容器状态 ==="
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}"
echo ""

echo "=== 系统资源使用情况 ==="
echo "CPU 使用率:"
top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//'

echo ""
echo "内存使用情况:"
free -h

echo ""
echo "磁盘使用情况:"
df -h | grep -E '^/dev/'

if command -v nvidia-smi &> /dev/null; then
    echo ""
    echo "=== GPU 使用情况 ==="
    nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits
fi

echo ""
echo "=== 最新日志 ==="
if [[ -d "logs" ]]; then
    find logs -name "*.log" -type f -exec ls -la {} \; | tail -5
else
    echo "暂无日志文件"
fi
EOF

    chmod +x $PROJECT_DIR/monitor.sh
    log_info "监控脚本创建完成: $PROJECT_DIR/monitor.sh"
}

# 显示使用说明
show_usage() {
    cat << EOF

🎉 DynSyn 云服务器部署完成！

📁 项目目录: $PROJECT_DIR
🐳 Docker 镜像: $DOCKER_IMAGE

🚀 快速开始:
1. 开始训练:
   cd $PROJECT_DIR && ./run_training.sh

2. 使用特定配置训练:
   cd $PROJECT_DIR && ./run_training.sh configs/DynSyn/myowalk-rough.json

3. 生成 DynSyn 数据:
   cd $PROJECT_DIR && ./generate_dynsyn.sh myoLegWalk

4. 监控系统状态:
   cd $PROJECT_DIR && ./monitor.sh

📝 可用的配置文件:
$(find $PROJECT_DIR/configs -name "*.json" -type f | head -10)

💡 提示:
- 日志保存在: $PROJECT_DIR/logs
- 结果保存在: $PROJECT_DIR/results
- 如需使用 Weights & Biases，请设置环境变量: export WANDB_API_KEY=your_key

🔧 故障排除:
- 查看 Docker 日志: docker logs <container_name>
- 重新拉取镜像: docker pull $DOCKER_IMAGE
- 系统监控: cd $PROJECT_DIR && ./monitor.sh

EOF
}

# 主函数
main() {
    echo "🚀 开始 DynSyn 云服务器一键部署..."
    echo ""
    
    detect_os
    update_system
    install_docker
    install_docker_compose
    install_nvidia_docker
    pull_docker_image
    setup_project
    create_run_script
    create_dynsyn_script
    create_monitor_script
    
    echo ""
    log_info "✅ 部署完成！重新登录以使 Docker 权限生效"
    show_usage
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 