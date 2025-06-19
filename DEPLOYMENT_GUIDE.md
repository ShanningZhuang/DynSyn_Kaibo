# DynSyn 云服务器部署指南

本指南将帮助你在按使用量付费的云服务器上高效部署和运行 DynSyn 项目，最大化减少环境创建时间和成本。

## 方案对比

| 方案 | 启动时间 | 部署复杂度 | 维护成本 | 推荐指数 |
|------|----------|------------|----------|----------|
| **Docker 容器化** | ⭐⭐⭐⭐⭐ (10s) | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 云服务商镜像快照 | ⭐⭐⭐⭐ (1-2min) | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| Conda/Poetry 环境 | ⭐⭐ (5-10min) | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |

## 🐳 方案一：Docker 容器化（推荐）

### 优势
- **极快启动**：容器启动只需几秒钟
- **环境一致性**：本地开发与云端部署完全一致
- **资源优化**：多阶段构建，镜像体积小
- **GPU 支持**：自动检测和配置 NVIDIA GPU
- **易于迁移**：支持多云平台部署

### 快速开始

1. **克隆项目并进入目录**
```bash
git clone https://github.com/ShanningZhuang/DynSyn_Kaibo.git
cd DynSyn_Kaibo
```

2. **一键设置环境**
```bash
./scripts/quick-start.sh setup
```

3. **构建 Docker 镜像**
```bash
./scripts/quick-start.sh build
```

4. **开始训练**
```bash
# 使用默认配置训练
./scripts/quick-start.sh train

# 使用特定配置文件
./scripts/quick-start.sh train configs/DynSyn/myowalk-rough.json
```

5. **生成 DynSyn 数据**
```bash
./scripts/quick-start.sh gen myoLegWalk
```

### 手动部署步骤

如果你更喜欢手动控制每个步骤：

```bash
# 1. 构建镜像
docker-compose build dynsyn

# 2. 运行训练
docker-compose run --rm dynsyn python -m dynsyn.sb3_runner.runner -f configs/DynSyn/myowalk.json

# 3. 启动开发环境（可选）
docker-compose --profile dev up -d
```

### GPU 支持配置

对于有 GPU 的云服务器：

```bash
# 检查 GPU
nvidia-smi

# 测试 NVIDIA Docker
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi

# 如果失败，安装 NVIDIA Docker 运行时
./scripts/quick-start.sh setup
```

## 📸 方案二：云服务商镜像/快照

### 适用的云服务商
- **AWS**: AMI (Amazon Machine Image)
- **阿里云**: 自定义镜像
- **腾讯云**: 自定义镜像
- **Google Cloud**: Machine Image
- **Azure**: Custom Image

### 创建自定义镜像步骤

1. **创建基础实例并安装环境**
```bash
# 安装系统依赖
sudo apt update && sudo apt install -y python3.9 python3-pip git

# 安装 Poetry
curl -sSL https://install.python-poetry.org | python3 -

# 克隆并安装项目
git clone https://github.com/ShanningZhuang/DynSyn_Kaibo.git
cd DynSyn_Kaibo
poetry install
```

2. **创建快照/镜像**
- 在云服务商控制台中创建当前实例的快照
- 为镜像添加描述标签（如：DynSyn-v1.0-Python3.9）

3. **使用镜像快速启动**
- 从自定义镜像创建新实例
- 启动时间：1-2 分钟

### 成本对比
- 镜像存储费用：通常 $0.05/GB/月
- 相比重复安装可节省：80% 的启动时间

## 🔧 方案三：配置管理自动化

### 使用 Ansible

1. **安装 Ansible**
```bash
pip install ansible
```

2. **创建 playbook**
```yaml
# ansible/setup.yml
---
- hosts: all
  become: yes
  tasks:
    - name: Update system
      apt:
        update_cache: yes
        
    - name: Install Python 3.9
      apt:
        name: python3.9
        state: present
        
    - name: Install Poetry
      shell: curl -sSL https://install.python-poetry.org | python3 -
      
    - name: Clone DynSyn
      git:
        repo: https://github.com/ShanningZhuang/DynSyn_Kaibo.git
        dest: /opt/dynsyn
        
    - name: Install dependencies
      shell: cd /opt/dynsyn && poetry install
```

3. **部署到云服务器**
```bash
ansible-playbook -i server_ip, setup.yml
```

## 💰 成本优化建议

### 1. 选择合适的实例类型
- **CPU 密集型**：选择计算优化型实例
- **需要 GPU**：选择 GPU 实例（如 AWS p3, 阿里云 gn6i）
- **内存需求**：此项目建议至少 8GB RAM

### 2. 使用竞价实例/抢占式实例
- AWS Spot Instances：可节省 50-90% 成本
- 阿里云抢占式实例：可节省 80% 成本
- 适合训练任务，支持检查点恢复

### 3. 数据存储优化
```bash
# 将大文件存储在对象存储中
# AWS S3, 阿里云 OSS, 腾讯云 COS

# 训练开始前下载数据
aws s3 sync s3://your-bucket/dynsyn-data ./data/

# 训练结束后上传结果
aws s3 sync ./logs/ s3://your-bucket/results/
```

### 4. 自动化关机
```bash
# 在训练脚本中添加自动关机
echo "sudo shutdown -h +5" | at now
```

## 🚀 实际部署示例

### AWS 上的完整部署流程

1. **启动 EC2 实例**
```bash
# 使用 AWS CLI
aws ec2 run-instances \
    --image-id ami-0c02fb55956c7d316 \
    --instance-type g4dn.xlarge \
    --key-name your-key \
    --security-group-ids sg-your-sg \
    --user-data file://user-data.sh
```

2. **user-data.sh 内容**
```bash
#!/bin/bash
yum update -y
yum install -y docker git
systemctl start docker
usermod -a -G docker ec2-user

# 安装 Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# 克隆项目
cd /home/ec2-user
git clone https://github.com/ShanningZhuang/DynSyn_Kaibo.git
cd DynSyn_Kaibo

# 构建并启动
docker-compose build dynsyn
docker-compose run --rm dynsyn python -m dynsyn.sb3_runner.runner -f configs/DynSyn/myowalk.json
```

### 阿里云 ECS 部署

```bash
# 创建实例
aliyun ecs RunInstances \
    --RegionId cn-hangzhou \
    --ImageId ubuntu_20_04_x64_20G_alibase_20210521.vhd \
    --InstanceType ecs.gn6i-c4g1.xlarge \
    --InternetMaxBandwidthOut 100
```

## 🔍 监控和日志

### 1. 使用 Weights & Biases
```bash
# 设置 WANDB API Key
export WANDB_API_KEY=your_api_key

# 在配置文件中启用 wandb
docker-compose run --rm \
    -e WANDB_API_KEY=$WANDB_API_KEY \
    dynsyn python -m dynsyn.sb3_runner.runner -f configs/DynSyn/myowalk.json
```

### 2. 本地日志管理
```bash
# 查看训练日志
docker-compose logs -f dynsyn

# 备份日志到云存储
tar -czf logs-$(date +%Y%m%d).tar.gz logs/
aws s3 cp logs-$(date +%Y%m%d).tar.gz s3://your-bucket/backups/
```

## 🎯 最佳实践总结

1. **开发阶段**：使用本地 Docker 环境进行快速迭代
2. **训练阶段**：使用云服务器 + Docker 进行大规模训练
3. **数据管理**：使用对象存储管理大文件，本地 SSD 存储训练数据
4. **成本控制**：使用竞价实例 + 自动关机 + 定期清理
5. **监控告警**：设置训练完成通知和异常告警

## 🆘 故障排除

### 常见问题

1. **内存不足**
```bash
# 增加 swap 空间
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

2. **GPU 不被识别**
```bash
# 检查 NVIDIA 驱动
nvidia-smi

# 重新安装 NVIDIA Docker
./scripts/quick-start.sh setup
```

3. **网络问题**
```bash
# 使用国内镜像加速
docker run --rm -v /etc/docker:/etc/docker alpine sh -c "echo '{\"registry-mirrors\":[\"https://registry.docker-cn.com\"]}' > /etc/docker/daemon.json"
sudo systemctl restart docker
```

通过这个完整的部署方案，你可以在云服务器上实现：
- **10 秒内启动训练环境**
- **节省 70%+ 的环境准备时间**
- **自动化的资源管理和成本控制** 