#!/bin/bash

# 🔄 重置管理员凭据脚本
# 用于删除旧的 init.json 文件，以便使用新的环境变量重新初始化

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 检查是否在项目根目录
if [ ! -f "docker-compose.yml" ]; then
    print_error "请在项目根目录运行此脚本"
    exit 1
fi

INIT_FILE="./data/init.json"

if [ ! -f "$INIT_FILE" ]; then
    print_warning "未找到 $INIT_FILE 文件"
    print_info "容器首次启动时会自动创建此文件"
    exit 0
fi

print_info "当前管理员凭据："
cat "$INIT_FILE" | grep -E "(adminUsername|adminPassword)" | sed 's/^/   /'

echo ""
print_warning "删除此文件后，容器重启时会使用 .env 文件中的 ADMIN_USERNAME 和 ADMIN_PASSWORD 重新初始化"
read -p "确认删除 $INIT_FILE 并重启容器？(y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "已取消操作"
    exit 0
fi

# 备份旧文件
BACKUP_FILE="./data/init.json.backup.$(date +%Y%m%d_%H%M%S)"
cp "$INIT_FILE" "$BACKUP_FILE"
print_info "已备份到: $BACKUP_FILE"

# 删除 init.json
rm -f "$INIT_FILE"
print_success "已删除 $INIT_FILE"

# 检查是否使用 docker-compose
if command -v docker-compose &> /dev/null || docker compose version &> /dev/null 2>&1; then
    print_info "重启容器以应用新的管理员凭据..."
    
    # 尝试使用 docker compose (新版本)
    if docker compose version &> /dev/null 2>&1; then
        docker compose restart claude-relay
    else
        docker-compose restart claude-relay
    fi
    
    print_success "容器已重启"
    print_info "等待服务启动..."
    sleep 3
    
    # 显示新的凭据
    if [ -f "$INIT_FILE" ]; then
        print_success "新的管理员凭据："
        cat "$INIT_FILE" | grep -E "(adminUsername|adminPassword)" | sed 's/^/   /'
    else
        print_warning "请查看容器日志获取新的管理员凭据："
        echo "   docker-compose logs claude-relay | grep -i admin"
    fi
else
    print_warning "未检测到 docker-compose"
    print_info "请手动重启容器："
    echo "   docker-compose restart claude-relay"
    echo "   或"
    echo "   docker compose restart claude-relay"
fi

