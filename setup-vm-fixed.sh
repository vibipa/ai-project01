#!/bin/bash

echo "🐧 Azure Ubuntu VM + Ollama + Open WebUI - Automated Setup"
echo "=========================================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}✓ Running on Azure VM${NC}"
echo ""

# Update system
echo -e "${BLUE}Step 1: Updating system packages...${NC}"
sudo apt update && sudo apt upgrade -y
echo -e "${GREEN}✓ System updated${NC}"
echo ""

# Install Docker
echo -e "${BLUE}Step 2: Installing Docker...${NC}"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    echo -e "${GREEN}✓ Docker installed${NC}"
    echo -e "${BLUE}Note: You need to log out and back in for docker group to take effect${NC}"
    echo -e "${BLUE}Or run: newgrp docker${NC}"
else
    echo -e "${GREEN}✓ Docker already installed${NC}"
fi
echo ""

# Install Ollama
echo -e "${BLUE}Step 3: Installing Ollama...${NC}"
if ! command -v ollama &> /dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
    echo -e "${GREEN}✓ Ollama installed${NC}"
else
    echo -e "${GREEN}✓ Ollama already installed${NC}"
fi

sleep 5
echo ""

# Pull model
echo -e "${BLUE}Step 4: Pulling Ollama model (this may take 5-10 minutes)...${NC}"
echo "Downloading qwen2.5:7b (4.7GB)..."
ollama pull qwen2.5:7b
echo -e "${GREEN}✓ Model downloaded${NC}"
echo ""

# Create flight assistant model
echo -e "${BLUE}Step 5: Creating flight assistant model...${NC}"
cat > /tmp/Modelfile << 'ENDMODELFILE'
FROM qwen2.5:7b

SYSTEM """You are a helpful flight status assistant. You have access to real-time flight data through tools. 
When users ask about flights, use the available tools to get accurate information.
Be concise and friendly in your responses."""

PARAMETER num_ctx 8192
PARAMETER temperature 0.7
ENDMODELFILE

ollama create flight-assistant -f /tmp/Modelfile
rm /tmp/Modelfile
echo -e "${GREEN}✓ Flight assistant model created${NC}"
echo ""

# Install Open WebUI
echo -e "${BLUE}Step 6: Installing Open WebUI...${NC}"

# Check if user is in docker group, if not, use sudo
if groups | grep -q docker; then
    docker run -d \
      --name open-webui \
      -p 3000:8080 \
      -v open-webui:/app/backend/data \
      --add-host=host.docker.internal:host-gateway \
      --restart always \
      ghcr.io/open-webui/open-webui:main
else
    echo -e "${BLUE}Running with sudo (docker group not active yet)${NC}"
    sudo docker run -d \
      --name open-webui \
      -p 3000:8080 \
      -v open-webui:/app/backend/data \
      --add-host=host.docker.internal:host-gateway \
      --restart always \
      ghcr.io/open-webui/open-webui:main
fi

echo "Waiting for Open WebUI to start..."
sleep 10

# Check if container is running (with or without sudo)
if docker ps 2>/dev/null | grep -q open-webui || sudo docker ps | grep -q open-webui; then
    echo -e "${GREEN}✓ Open WebUI installed and running${NC}"
else
    echo -e "${RED}✗ Open WebUI failed to start${NC}"
    echo "Checking logs..."
    docker logs open-webui 2>/dev/null || sudo docker logs open-webui
    exit 1
fi
echo ""

# Install Python dependencies
echo -e "${BLUE}Step 7: Installing Python dependencies...${NC}"
sudo apt install python3-pip -y
python3 -m pip install --user fastmcp httpx
echo -e "${GREEN}✓ Python dependencies installed${NC}"
echo ""

# Create flight tools directory
echo -e "${BLUE}Step 8: Creating MCP flight tools...${NC}"
mkdir -p ~/flight-tools
cd ~/flight-tools

# Get Aviation API key
echo ""
echo -e "${BLUE}Aviation API Key Setup:${NC}"
echo "Get your free API key from: https://aviationstack.com"
read -p "Enter your Aviation API key (or press Enter to skip): " AVIATION_API_KEY

if [ -z "$AVIATION_API_KEY" ]; then
    echo -e "${BLUE}No API key provided. You can add it later by editing ~/flight-tools/flight_mcp_server.py${NC}"
    AVIATION_API_KEY="your_aviation_api_key_here"
fi

# Create MCP server with proper escaping
cat > ~/flight-tools/flight_mcp_server.py << 'ENDPYTHON'
#!/usr/bin/env python3
"""MCP Server for Flight Status Tools"""

import json
import httpx
from typing import Any, Dict
from fastmcp import FastMCP

mcp = FastMCP("flight-tools")
AVIATION_API_KEY = "REPLACE_API_KEY_HERE"
AVIATION_BASE_URL = "http://api.aviationstack.com/v1"

@mcp.tool()
async def get_flight_status(flight_iata: str) -> Dict[str, Any]:
    """Get real-time flight status information.
    
    Args:
        flight_iata: The IATA flight number (e.g., 'AA100', 'BA123')
    
    Returns:
        Flight status including departure, arrival, delays, gates, and terminals
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{AVIATION_BASE_URL}/flights",
                params={"access_key": AVIATION_API_KEY, "flight_iata": flight_iata},
                timeout=10.0
            )
            response.raise_for_status()
            data = response.json()
            
            if not data.get("data"):
                return {"success": False, "error": f"No flight found for {flight_iata}"}
            
            flight = data["data"][0]
            return {
                "success": True,
                "flight_number": flight.get("flight", {}).get("iata"),
                "airline": flight.get("airline", {}).get("name"),
                "status": flight.get("flight_status"),
                "departure": {
                    "airport": flight.get("departure", {}).get("airport"),
                    "iata": flight.get("departure", {}).get("iata"),
                    "scheduled": flight.get("departure", {}).get("scheduled"),
                    "actual": flight.get("departure", {}).get("actual"),
                    "terminal": flight.get("departure", {}).get("terminal"),
                    "gate": flight.get("departure", {}).get("gate")
                },
                "arrival": {
                    "airport": flight.get("arrival", {}).get("airport"),
                    "iata": flight.get("arrival", {}).get("iata"),
                    "scheduled": flight.get("arrival", {}).get("scheduled"),
                    "estimated": flight.get("arrival", {}).get("estimated"),
                    "terminal": flight.get("arrival", {}).get("terminal"),
                    "gate": flight.get("arrival", {}).get("gate")
                }
            }
    except Exception as e:
        return {"success": False, "error": str(e)}

@mcp.tool()
async def search_flights_by_route(departure_iata: str, arrival_iata: str) -> Dict[str, Any]:
    """Search for flights between two airports.
    
    Args:
        departure_iata: Departure airport IATA code (e.g., 'JFK', 'LAX')
        arrival_iata: Arrival airport IATA code (e.g., 'LHR', 'CDG')
    
    Returns:
        Available flights on this route
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{AVIATION_BASE_URL}/flights",
                params={
                    "access_key": AVIATION_API_KEY,
                    "dep_iata": departure_iata,
                    "arr_iata": arrival_iata
                },
                timeout=10.0
            )
            response.raise_for_status()
            data = response.json()
            
            if not data.get("data"):
                return {
                    "success": False,
                    "error": f"No flights found from {departure_iata} to {arrival_iata}"
                }
            
            flights = []
            for flight in data["data"][:5]:
                flights.append({
                    "flight_number": flight.get("flight", {}).get("iata"),
                    "airline": flight.get("airline", {}).get("name"),
                    "status": flight.get("flight_status"),
                    "departure_time": flight.get("departure", {}).get("scheduled"),
                    "arrival_time": flight.get("arrival", {}).get("scheduled")
                })
            
            return {
                "success": True,
                "route": f"{departure_iata} -> {arrival_iata}",
                "flights": flights
            }
    except Exception as e:
        return {"success": False, "error": str(e)}

if __name__ == "__main__":
    mcp.run()
ENDPYTHON

# Replace API key in the file
sed -i "s/REPLACE_API_KEY_HERE/${AVIATION_API_KEY}/" ~/flight-tools/flight_mcp_server.py

chmod +x ~/flight-tools/flight_mcp_server.py
echo -e "${GREEN}✓ MCP flight tools created${NC}"
echo ""

# Install Nginx
echo -e "${BLUE}Step 9: Installing and configuring Nginx...${NC}"
sudo apt install nginx -y

# Create Nginx config with proper escaping
sudo tee /etc/nginx/sites-available/openwebui > /dev/null << 'ENDNGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
    }
}
ENDNGINX

sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/openwebui /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

echo -e "${GREEN}✓ Nginx configured${NC}"
echo ""

PUBLIC_IP=$(curl -s ifconfig.me)

echo "=========================================================="
echo -e "${GREEN}✨ Installation Complete!${NC}"
echo "=========================================================="
echo ""
echo -e "${BLUE}Your Flight AI Assistant is ready!${NC}"
echo ""
echo "Access Open WebUI at:"
echo -e "  ${GREEN}http://${PUBLIC_IP}${NC}"
echo ""
echo "Next steps:"
echo "  1. Open the URL in your browser"
echo "  2. Create an admin account (first user)"
echo "  3. Start chatting with your AI assistant!"
echo ""
echo "Example queries to try:"
echo "  • What's the status of flight AA100?"
echo "  • Show me flights from JFK to LAX"
echo "  • Is flight BA456 delayed?"
echo ""
echo "Model available: flight-assistant (qwen2.5:7b)"
echo ""
echo "Useful commands:"
echo "  • Check status: docker ps (or: sudo docker ps)"
echo "  • View logs: docker logs open-webui"
echo "  • Restart: docker restart open-webui"
echo "  • List models: ollama list"
echo ""
if [ "$AVIATION_API_KEY" == "your_aviation_api_key_here" ]; then
    echo -e "${BLUE}Note: Remember to add your Aviation API key to:${NC}"
    echo "  ~/flight-tools/flight_mcp_server.py"
    echo ""
fi
echo -e "${GREEN}🎉 Enjoy your AI assistant!${NC}"
