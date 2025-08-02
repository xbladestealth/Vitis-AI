#!/bin/bash
# Copyright 2022 Xilinx Inc.

# Function to prompt user for confirmation
confirm() {
  echo -n "Do you agree to the terms and wish to proceed [y/n]? "
  read REPLY
  case "$REPLY" in
    [Yy]) ;;
    [Nn]) exit 0 ;;
    *) confirm ;;
  esac
  REPLY=""
}

# Check if running in Bash
if [ -z "$BASH_VERSION" ]; then
  echo "Error: This script requires Bash. Run it with 'bash $0'."
  exit 1
fi

# Display help message
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "Usage: $0 <Vitis_AI_DOCKER_NAME> [command]"
  exit 2
fi

# Check if image name is provided
if [ -z "$1" ]; then
  echo "Error: Vitis AI Docker image name required"
  echo "Usage: $0 <Vitis_AI_DOCKER_NAME> [command]"
  exit 2
fi

# Get current directory and user details
HERE=$(pwd -P)  # Absolute path of current directory
USER=$(whoami)
UID=$(id -u)
GID=$(id -g)

# Define Docker repository and image details
DOCKER_REPO="xilinx/"
BRAND="vitis-ai"
VERSION="latest"
CPU_IMAGE_TAG="${DOCKER_REPO}${BRAND}-cpu:${VERSION}"
GPU_IMAGE_TAG="${DOCKER_REPO}${BRAND}-gpu:${VERSION}"
IMAGE_NAME="$1"

# Set default command
shift
DEFAULT_COMMAND="$*"
if [ -z "$DEFAULT_COMMAND" ]; then
  DEFAULT_COMMAND="bash"
fi

# Set Docker run mode (interactive terminal)
DETACHED="-it"

# Find and map device files
docker_devices=""
for dev in /dev/xclmgmt* /dev/dri/renderD* /dev/kfd*; do
  if [ -e "$dev" ]; then
    docker_devices="$docker_devices --device=$dev"
  fi
done

# Check if script is run from the correct directory
DOCKER_RUN_DIR=$(dirname "$0")
if [ "$HERE" != "$(cd "$DOCKER_RUN_DIR" && pwd)" ]; then
  echo "WARNING: Please start 'docker_run.sh' from the Vitis-AI source directory"
fi

# Define Docker run parameters as a single string
docker_run_params="-v /dev/shm:/dev/shm \
  -v /opt/xilinx/dsa:/opt/xilinx/dsa \
  -v /opt/xilinx/overlaybins:/opt/xilinx/overlaybins \
  -e USER=$USER -e UID=$UID -e GID=$GID \
  -v $DOCKER_RUN_DIR:/vitis_ai_home \
  -v $HERE:/workspace \
  -w /workspace \
  --rm \
  --network=host \
  $DETACHED"

# Display license prompt if .confirm file doesn't exist
if [ ! -f ".confirm" ]; then
  if echo "$IMAGE_NAME" | grep -q "gpu"; then
    arch="gpu"
  elif echo "$IMAGE_NAME" | grep -q "rocm"; then
    arch="rocm"
  else
    arch="cpu"
  fi

  prompt_file="./docker/dockerfiles/PROMPT/PROMPT_${arch}.txt"
  if [ -f "$prompt_file" ]; then
    cat "$prompt_file" | less -P "Press any key to continue..."
    confirm
  else
    echo "Warning: Prompt file $prompt_file not found. Skipping license prompt."
  fi
  touch .confirm
fi

# Pull the Docker image
echo "Pulling Docker image: $IMAGE_NAME"
docker pull "$IMAGE_NAME"

# Run Docker container based on architecture
if echo "$IMAGE_NAME" | grep -q "gpu"; then
  docker run \
    $docker_devices \
    --gpus all \
    $docker_run_params \
    "$IMAGE_NAME" \
    "$DEFAULT_COMMAND"
elif echo "$IMAGE_NAME" | grep -q "rocm"; then
  docker run \
    $docker_devices \
    --group-add=render \
    --group-add=video \
    --ipc=host \
    --cap-add=SYS_PTRACE \
    --security-opt seccomp=unconfined \
    $docker_run_params \
    "$IMAGE_NAME" \
    "$DEFAULT_COMMAND"
else
  docker run \
    $docker_devices \
    $docker_run_params \
    "$IMAGE_NAME" \
    "$DEFAULT_COMMAND"
fi