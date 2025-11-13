#!/bin/bash

# 🐳 Claude Relay Service 跨平台构建和推送脚本
# 支持多架构构建（amd64, arm64）并推送到 Docker Hub

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
DOCKER_USERNAME="${DOCKER_USERNAME:-klause}"
IMAGE_NAME="${IMAGE_NAME:-claude-relay-service}"
VERSION="${VERSION:-latest}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

# 完整镜像名称
FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}"

# 打印带颜色的消息
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

# 显示使用说明
show_usage() {
    cat << EOF
用法: $0 [选项]

选项:
    -u, --username USERNAME    Docker Hub 用户名 (默认: ${DOCKER_USERNAME})
    -i, --image IMAGE_NAME     镜像名称 (默认: ${IMAGE_NAME})
    -v, --version VERSION      版本标签 (默认: ${VERSION})
    -p, --platforms PLATFORMS  平台列表，逗号分隔 (默认: ${PLATFORMS})
    -t, --tag TAG              额外标签（可多次使用）
    --no-push                  只构建，不推送
    --no-cache                 不使用缓存构建
    -h, --help                 显示此帮助信息

环境变量:
    DOCKER_USERNAME            Docker Hub 用户名
    IMAGE_NAME                 镜像名称
    VERSION                    版本标签
    PLATFORMS                  平台列表

示例:
    # 使用默认配置构建并推送
    $0

    # 指定用户名和版本
    $0 -u myusername -v v1.0.0

    # 只构建不推送
    $0 --no-push

    # 多标签推送
    $0 -v v1.0.0 -t latest -t stable

    # 只构建 amd64 平台
    $0 -p linux/amd64

EOF
}

# 解析命令行参数
EXTRA_TAGS=()
PUSH=true
NO_CACHE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--username)
            DOCKER_USERNAME="$2"
            FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}"
            shift 2
            ;;
        -i|--image)
            IMAGE_NAME="$2"
            FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -p|--platforms)
            PLATFORMS="$2"
            shift 2
            ;;
        -t|--tag)
            EXTRA_TAGS+=("$2")
            shift 2
            ;;
        --no-push)
            PUSH=false
            shift
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "未知选项: $1"
            show_usage
            exit 1
            ;;
    esac
done

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    print_error "Docker 未安装，请先安装 Docker"
    exit 1
fi

# 检查是否已登录 Docker Hub
if [ "$PUSH" = true ]; then
    if ! docker info | grep -q "Username"; then
        print_warning "未检测到 Docker Hub 登录信息"
        print_info "请先运行: docker login"
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# 检查并设置 Docker Buildx
print_info "检查 Docker Buildx..."

if ! docker buildx version &> /dev/null; then
    print_error "Docker Buildx 未安装或不可用"
    print_info "请确保 Docker 版本 >= 19.03"
    exit 1
fi

# 创建或使用 buildx builder
BUILDER_NAME="claude-relay-builder"

if ! docker buildx ls | grep -q "$BUILDER_NAME"; then
    print_info "创建新的 buildx builder: $BUILDER_NAME"
    docker buildx create --name "$BUILDER_NAME" --use --bootstrap
    print_success "Builder 创建成功"
else
    print_info "使用现有 builder: $BUILDER_NAME"
    docker buildx use "$BUILDER_NAME"
    # 确保 builder 已启动
    docker buildx inspect --bootstrap &> /dev/null || true
fi

# 显示构建信息
print_info "构建配置:"
echo "  镜像名称: ${FULL_IMAGE_NAME}"
echo "  版本标签: ${VERSION}"
echo "  平台: ${PLATFORMS}"
if [ ${#EXTRA_TAGS[@]} -gt 0 ]; then
    echo "  额外标签: ${EXTRA_TAGS[*]}"
fi
echo "  推送: $([ "$PUSH" = true ] && echo "是" || echo "否")"
echo "  缓存: $([ -z "$NO_CACHE" ] && echo "使用" || echo "不使用")"
echo ""

# 构建标签列表
TAGS=("${FULL_IMAGE_NAME}:${VERSION}")
for tag in "${EXTRA_TAGS[@]}"; do
    TAGS+=("${FULL_IMAGE_NAME}:${tag}")
done

# 构建标签参数
TAG_ARGS=""
for tag in "${TAGS[@]}"; do
    TAG_ARGS="${TAG_ARGS} --tag ${tag}"
done

# 构建命令
BUILD_CMD="docker buildx build \
    --platform ${PLATFORMS} \
    ${TAG_ARGS} \
    ${NO_CACHE} \
    --file Dockerfile \
    ."

# 如果启用推送，添加 --push 参数
if [ "$PUSH" = true ]; then
    BUILD_CMD="${BUILD_CMD} --push"
else
    BUILD_CMD="${BUILD_CMD} --load"
    # --load 只支持单平台
    if [ "$PLATFORMS" != "${PLATFORMS%%,*}" ]; then
        print_warning "--load 模式只支持单平台，将使用第一个平台: ${PLATFORMS%%,*}"
        BUILD_CMD="docker buildx build \
            --platform ${PLATFORMS%%,*} \
            ${TAG_ARGS} \
            ${NO_CACHE} \
            --file Dockerfile \
            --load \
            ."
    fi
fi

# 执行构建
print_info "开始构建镜像..."
print_info "执行命令: ${BUILD_CMD}"
echo ""

if eval "$BUILD_CMD"; then
    print_success "镜像构建完成！"
    echo ""
    
    if [ "$PUSH" = true ]; then
        print_success "镜像已推送到 Docker Hub:"
        for tag in "${TAGS[@]}"; do
            echo "  - ${tag}"
        done
        echo ""
        print_info "拉取命令:"
        echo "  docker pull ${TAGS[0]}"
    else
        print_success "镜像已构建到本地:"
        for tag in "${TAGS[@]}"; do
            echo "  - ${tag}"
        done
    fi
else
    print_error "镜像构建失败"
    exit 1
fi

