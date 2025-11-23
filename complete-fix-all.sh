#!/bin/bash

# ============================================================
# Complete Open WebUI + Ollama Fix Script
# Fixes all connection issues and gets models working
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════╗
║   Complete Open WebUI + Ollama Fix          ║
║   Fixes connection and model issues         ║
╚══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ============================================================
# STEP 1: Configure Ollama to listen on all interfaces
# ============================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 1: Configuring Ollama${NC}"
echo -e "${BLUE}========================================${NC}"

echo "Making Ollama accessible to Docker containers..."

sudo tee /etc/systemd/system/ollama.service > /dev/null << 'OLLAMASERVICE'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
Environment="OLLAMA_HOST=0.0.0.0:11434"

[Install]
WantedBy=default.target
OLLAMASERVICE

echo -e "${GREEN}✓ Ollama service file updated${NC}"

# Reload and restart Ollama
sudo systemctl daemon-reload
sudo systemctl restart ollama
sleep 5

# Verify Ollama is running
if systemctl is-active --quiet ollama; then
    echo -e "${GREEN}✓ Ollama service is running${NC}"
else
    echo -e "${RED}✗ Ollama failed to start${NC}"
    sudo systemctl status ollama --no-pager
    exit 1
fi

# Check what Ollama is listening on
echo "Ollama is now listening on:"
sudo ss -tlnp | grep 11434 || sudo netstat -tlnp | grep 11434

echo ""

# ============================================================
# STEP 2: Ensure we have models
# ============================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 2: Checking Models${NC}"
echo -e "${BLUE}========================================${NC}"

echo "Current models:"
ollama list

if ! ollama list | grep -q "qwen2.5:7b"; then
    echo -e "${YELLOW}Model not found. Downloading qwen2.5:7b (4.7GB, takes 5-10 minutes)...${NC}"
    ollama pull qwen2.5:7b
    echo -e "${GREEN}✓ Model downloaded${NC}"
else
    echo -e "${GREEN}✓ qwen2.5:7b already installed${NC}"
fi

echo ""
echo "Final model list:"
ollama list

echo ""

# ============================================================
# STEP 3: Test Ollama API
# ============================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 3: Testing Ollama API${NC}"
echo -e "${BLUE}========================================${NC}"

# Test from localhost
echo "Testing from localhost (127.0.0.1)..."
if curl -s http://127.0.0.1:11434/api/tags > /dev/null; then
    echo -e "${GREEN}✓ Ollama API responds on 127.0.0.1${NC}"
    MODELS=$(curl -s http://127.0.0.1:11434/api/tags | python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join([m['name'] for m in data.get('models', [])]))")
    if [ -n "$MODELS" ]; then
        echo "Available models:"
        echo "$MODELS" | while read model; do
            echo "  - $model"
        done
    fi
else
    echo -e "${RED}✗ Ollama API not responding${NC}"
    exit 1
fi

# Test from docker bridge IP
echo ""
echo "Testing from Docker bridge (172.17.0.1)..."
if curl -s http://172.17.0.1:11434/api/tags > /dev/null; then
    echo -e "${GREEN}✓ Ollama API responds on 172.17.0.1${NC}"
else
    echo -e "${RED}✗ Ollama not accessible from Docker bridge${NC}"
    echo "This might cause issues, but we'll continue..."
fi

echo ""

# ============================================================
# STEP 4: Stop and remove old Open WebUI
# ============================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 4: Removing Old Container${NC}"
echo -e "${BLUE}========================================${NC}"

if docker ps -a | grep -q open-webui; then
    echo "Stopping existing Open WebUI container..."
    docker stop open-webui 2>/dev/null || true
    docker rm open-webui 2>/dev/null || true
    echo -e "${GREEN}✓ Old container removed${NC}"
else
    echo "No existing container found"
fi

echo ""

# ============================================================
# STEP 5: Start Open WebUI with correct configuration
# ============================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 5: Starting Open WebUI${NC}"
echo -e "${BLUE}========================================${NC}"

echo "Creating Open WebUI container with proper Ollama connection..."

# Using bridge network with 172.17.0.1 (most reliable)
docker run -d \
  --name open-webui \
  -p 8080:8080 \
  -v open-webui:/app/backend/data \
  -e OLLAMA_BASE_URL=http://172.17.0.1:11434 \
  -e ENABLE_OLLAMA_API=true \
  -e WEBUI_AUTH=false \
  --restart always \
  ghcr.io/open-webui/open-webui:main

echo "Waiting for Open WebUI to start (20 seconds)..."
sleep 20

# Check if container is running
if docker ps | grep -q open-webui; then
    echo -e "${GREEN}✓ Open WebUI container is running${NC}"
else
    echo -e "${RED}✗ Container failed to start${NC}"
    docker logs open-webui 2>&1 | tail -20
    exit 1
fi

echo ""

# ============================================================
# STEP 6: Verify Open WebUI can reach Ollama
# ============================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 6: Testing Connection${NC}"
echo -e "${BLUE}========================================${NC}"

echo "Testing if Open WebUI can connect to Ollama..."
sleep 5  # Give it a moment to fully initialize

if docker exec open-webui curl -s http://172.17.0.1:11434/api/tags > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Open WebUI can connect to Ollama${NC}"
    
    echo ""
    echo "Models visible to Open WebUI:"
    docker exec open-webui curl -s http://172.17.0.1:11434/api/tags | python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join([f\"  - {m['name']}\" for m in data.get('models', [])]))" 2>/dev/null || echo "  (Could not parse models)"
else
    echo -e "${YELLOW}⚠ Warning: Container cannot reach Ollama via 172.17.0.1${NC}"
    echo "Trying to diagnose..."
    docker exec open-webui curl -v http://172.17.0.1:11434/api/tags 2>&1 | tail -10
fi

echo ""

# ============================================================
# STEP 7: Test Open WebUI web interface
# ============================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 7: Testing Web Interface${NC}"
echo -e "${BLUE}========================================${NC}"

if curl -s http://localhost:8080 > /dev/null; then
    echo -e "${GREEN}✓ Open WebUI web interface is responding${NC}"
else
    echo -e "${RED}✗ Web interface not responding${NC}"
fi

echo ""

# ============================================================
# STEP 8: Update Nginx configuration
# ============================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 8: Configuring Nginx${NC}"
echo -e "${BLUE}========================================${NC}"

if command -v nginx &> /dev/null; then
    echo "Updating Nginx configuration to proxy to port 8080..."
    
    sudo tee /etc/nginx/sites-available/default > /dev/null << 'NGINXCONF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /ws {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINXCONF

    # Test nginx config
    if sudo nginx -t 2>/dev/null; then
        sudo systemctl restart nginx
        echo -e "${GREEN}✓ Nginx configured and restarted${NC}"
    else
        echo -e "${YELLOW}⚠ Nginx config test failed, but continuing...${NC}"
    fi
else
    echo "Nginx not installed, skipping..."
fi

echo ""

# ============================================================
# STEP 9: Check for errors in logs
# ============================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 9: Checking Logs${NC}"
echo -e "${BLUE}========================================${NC}"

echo "Recent Open WebUI logs:"
docker logs open-webui 2>&1 | tail -15

echo ""
echo "Looking for errors..."
ERRORS=$(docker logs open-webui 2>&1 | grep -i "error" | tail -5)
if [ -z "$ERRORS" ]; then
    echo -e "${GREEN}✓ No errors found in logs${NC}"
else
    echo -e "${YELLOW}⚠ Some errors found:${NC}"
    echo "$ERRORS"
fi

echo ""

# ============================================================
# FINAL SUMMARY
# ============================================================
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_VM_IP")

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✨ Setup Complete! ✨${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Access Open WebUI:${NC}"
echo "  🌐 Direct access:    http://$PUBLIC_IP:8080"
echo "  🌐 Via Nginx:        http://$PUBLIC_IP"
echo ""
echo -e "${BLUE}Installed Models:${NC}"
ollama list | tail -n +2 | awk '{print "  📦 " $1}'
echo ""
echo -e "${BLUE}What to do now:${NC}"
echo "  1. Open your browser to one of the URLs above"
echo "  2. Click the model dropdown at the top of the page"
echo "  3. Select 'qwen2.5:7b' from the list"
echo "  4. Start chatting!"
echo ""
echo -e "${BLUE}If model selector still doesn't work:${NC}"
echo "  1. Press F12 in your browser (Developer Tools)"
echo "  2. Go to Console tab"
echo "  3. Look for any errors (red text)"
echo "  4. In Open WebUI, go to Settings → Admin Panel → Connections"
echo "  5. Set Ollama URL to: http://172.17.0.1:11434"
echo "  6. Click Save and refresh the page"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "  View logs:           docker logs -f open-webui"
echo "  Restart container:   docker restart open-webui"
echo "  Check Ollama:        ollama list"
echo "  Test Ollama API:     curl http://172.17.0.1:11434/api/tags"
echo "  Check services:      sudo systemctl status ollama nginx"
echo ""
echo -e "${BLUE}Troubleshooting:${NC}"
echo "  If models don't appear, run:"
echo "    docker exec open-webui curl http://172.17.0.1:11434/api/tags"
echo ""
echo -e "${GREEN}🎉 Your AI Weather Assistant is ready!${NC}"
echo ""
