# Stop and remove existing container
docker stop open-webui
docker rm open-webui

# Run on port 8080
docker run -d \
  --name open-webui \
  -p 8080:8080 \
  -v open-webui:/app/backend/data \
  --add-host=host.docker.internal:host-gateway \
  -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
  -e WEBUI_AUTH=false \
  --restart always \
  ghcr.io/open-webui/open-webui:main

# Update Nginx config
sudo nano /etc/nginx/sites-available/default
