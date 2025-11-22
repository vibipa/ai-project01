#!/bin/bash

echo "🐧 Azure Ubuntu VM + Ollama + Open WebUI - Automated Setup"
echo "=========================================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Check if running on Azure VM
if [ ! -f /var/lib/cloud/instance/boot-finished ]; then
    echo -e "${BLUE}This script is designed to run on an Azure Ubuntu VM${NC}"
    echo "Please run this ON your Azure VM after SSH'ing in"
    echo ""
    echo "First, create your VM with:"
    echo "  ./create-azure-vm.sh"
    echo ""
    echo "Then SSH in and run this script"
    exit 1
fi

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

# Wait for Ollama to start
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
cat > /tmp/Modelfile << 'EOF'
FROM qwen2.5:7b

SYSTEM """You are a helpful flight status assistant. You have access to real-time flight data through tools. 
When users ask about flights, use the available tools to get accurate information.
Be concise and friendly in your responses."""

PARAMETER num_ctx 8192
PARAMETER temperature 0.7
EOF

ollama create flight-assistant -f /tmp/Modelfile
rm /tmp/Modelfile
echo -e "${GREEN}✓ Flight assistant model created${NC}"
echo ""

# Install Open WebUI
echo -e "${BLUE}Step 6: Installing Open WebUI...${NC}"
docker run -d \
  --name open-webui \
  -p 3000:8080 \
  -v open-webui:/app/backend/data \
  --add-host=host.docker.internal:host-gateway \
  --restart always \
  ghcr.io/open-webui/open-webui:main

# Wait for container to start
echo "Waiting for Open WebUI to start..."
sleep 10

if docker ps | grep -q open-webui; then
    echo -e "${GREEN}✓ Open WebUI installed and running${NC}"
else
    echo -e "${RED}✗ Open WebUI failed to start${NC}"
    docker logs open-webui
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
read -p "Enter your Aviation API key: " AVIATION_API_KEY

if [ -z "$AVIATION_API_KEY" ]; then
    echo -e "${RED}✗ API key is required${NC}"
    echo "You can add it later by editing ~/flight-tools/flight_mcp_server.py"
    AVIATION_API_KEY="your_aviation_api_key_here"
fi

# Create MCP server
cat > ~/flight-tools/flight_mcp_server.py << EOF
#!/usr/bin/env python3
"""
MCP Server for Flight Status Tools
Integrates with Open WebUI via function calling
"""

import json
import httpx
from typing import Any, Dict
from fastmcp import FastMCP

# Initialize MCP server
mcp = FastMCP("flight-tools")

# Configuration
AVIATION_API_KEY = "${AVIATION_API_KEY}"
AVIATION_BASE_URL = "http://api.aviationstack.com/v1"

@mcp.tool()
async def get_flight_status(flight_iata: str) -> Dict[str, Any]:
    """
    Get real-time flight status information.
    
    Args:
        flight_iata: The IATA flight number (e.g., 'AA100', 'BA123')
    
    Returns:
        Flight status including departure, arrival, delays, gates, and terminals
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{AVIATION_BASE_URL}/flights",
                params={
                    "access_key": AVIATION_API_KEY,
                    "flight_iata": flight_iata
                },
                timeout=10.0
            )
            response.raise_for_status()
            data = response.json()
            
            if not data.get("data"):
                return {
                    "success": False,
                    "error": f"No flight found for {flight_iata}"
                }
            
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
                },
                "aircraft": flight.get("aircraft", {}).get("registration"),
            }
    except Exception as e:
        return {
            "success": False,
            "error": f"Error fetching flight status: {str(e)}"
        }

@mcp.tool()
async def search_flights_by_route(departure_iata: str, arrival_iata: str) -> Dict[str, Any]:
    """
    Search for flights between two airports.
    
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
                "route": f"{departure_iata} → {arrival_iata}",
                "flights": flights
            }
    except Exception as e:
        return {
            "success": False,
            "error": f"Error searching flights: {str(e)}"
        }

if __name__ == "__main__":
    mcp.run()
EOF

chmod +x ~/flight-tools/flight_mcp_server.py
echo -e "${GREEN}✓ MCP flight tools created${NC}"
echo ""

# Install Nginx
echo -e "${BLUE}Step 9: Installing and configuring Nginx...${NC}"
sudo apt install nginx -y

# Create Nginx configuration
sudo cat > /etc/nginx/sites-available/openwebui << 'NGINX_EOF'
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
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
    }
}
NGINX_EOF

# Enable the site
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/openwebui /etc/nginx/sites-enabled/

# Test and restart Nginx
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

echo -e "${GREEN}✓ Nginx configured${NC}"
echo ""

# Get public IP
PUBLIC_IP=$(curl -s ifconfig.me)

echo "=========================================================="
echo -e "${GREEN}✨ Installation Complete!${NC}"
echo "=========================================================="
echo ""
echo -e "${BLUE}Your Flight AI Assistant is ready!${NC}"
echo ""
echo "Access Open WebUI at:"
echo -e "  ${GREEN}http://$PUBLIC_IP${NC}"
echo ""
echo "Next steps:"
echo "  1. Open the URL in your browser"
echo "  2. Create an admin account (first user)"
echo "  3. Go to Settings → Admin Panel → Tools"
echo "  4. Add MCP Server with:"
echo "     - Name: Flight Tools"
echo "     - Command: python3"
echo "     - Args: /home/$(whoami)/flight-tools/flight_mcp_server.py"
echo "  5. Enable the tool and start chatting!"
echo ""
echo "Try these example queries:"
echo "  • What's the status of flight AA100?"
echo "  • Show me flights from JFK to LAX"
echo "  • Is flight BA123 delayed?"
echo ""
echo "Model available:"
echo "  • flight-assistant (qwen2.5:7b with function calling)"
echo ""
echo "Installed components:"
echo "  ✓ Ollama (http://localhost:11434)"
echo "  ✓ Open WebUI (http://localhost:3000)"
echo "  ✓ MCP Flight Tools (~/flight-tools/)"
echo "  ✓ Nginx (reverse proxy on port 80)"
echo ""
echo "Useful commands:"
echo "  • Check status: docker ps"
echo "  • View logs: docker logs open-webui"
echo "  • Restart: docker restart open-webui"
echo "  • List models: ollama list"
echo ""
echo -e "${GREEN}🎉 Enjoy your AI assistant!${NC}"
