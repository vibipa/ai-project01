# 1. Stop everything
docker stop open-webui 2>/dev/null
docker rm open-webui 2>/dev/null
sudo systemctl stop nginx

# 2. Start Ollama first
sudo systemctl restart ollama
sleep 5

# 3. Start Open WebUI (use --network host for simplicity)
docker run -d \
  --name open-webui \
  --network host \
  -v open-webui:/app/backend/data \
  -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
  -e WEBUI_AUTH=false \
  --restart always \
  ghcr.io/open-webui/open-webui:main

# 4. Wait for Open WebUI to start
echo "Waiting for Open WebUI to start..."
sleep 15

# 5. Check if it's listening on port 3000
curl http://localhost:3000

# 6. Start Nginx
sudo systemctl start nginx

# 7. Check everything
docker ps
sudo systemctl status nginx
