#!/usr/bin/env bash
set -euo pipefail
# Install NVIDIA Container Toolkit and restart Docker so Immich can use the RTX 2060.
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed "s#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g" \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
echo "Toolkit installed. Starting Immich with CUDA..."
cd "$(dirname "$0")"
docker compose up -d
docker compose ps
echo "Verify GPU in ML container:"
docker exec immich_machine_learning python -c "import onnxruntime as ort; print(ort.get_available_providers())" 2>/dev/null || \
  docker logs immich_machine_learning --tail 30
