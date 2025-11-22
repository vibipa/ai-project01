#!/bin/bash

# ============================================================
# Azure VM Setup Script - Weather Assistant Edition
# ============================================================
# Sets up: Ollama + Open WebUI + Weather MCP Server
# Replaces aviationstack with OpenWeatherMap (free tier)
# ============================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════╗
║   Weather AI Assistant - Azure VM Setup     ║
║   Uses: Ollama + Open WebUI + Weather MCP   ║
╚══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   echo -e "${RED}❌ Please run as normal user, not root${NC}"
   exit 1
fi

echo -e "${YELLOW}📋 This script will:${NC}"
echo "  1. Update system packages"
echo "  2. Install Docker"
echo "  3. Install Ollama"
echo "  4. Download qwen2.5:7b model (~4.7GB)"
echo "  5. Install Open WebUI"
echo "  6. Set up Weather MCP server"
echo "  7. Configure Nginx reverse proxy"
echo ""
echo -e "${YELLOW}⏱️  Total time: ~15 minutes${NC}"
echo ""

# Set OpenWeatherMap API key
OPENWEATHER_API_KEY="749ca196cb81001a9987061749551ce1"

echo -e "${BLUE}🔑 OpenWeatherMap API Key${NC}"
echo -e "${GREEN}✓ API key configured${NC}"
echo ""

read -p "Continue with installation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled"
    exit 0
fi

echo ""
echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}Step 1: System Update${NC}"
echo -e "${BLUE}==================================${NC}"
sudo apt update
sudo apt upgrade -y
echo -e "${GREEN}✓ System updated${NC}"
echo ""

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}Step 2: Install Docker${NC}"
echo -e "${BLUE}==================================${NC}"

# Remove old Docker versions if any
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Install dependencies
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER

echo -e "${GREEN}✓ Docker installed${NC}"
echo ""

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}Step 3: Install Ollama${NC}"
echo -e "${BLUE}==================================${NC}"
curl -fsSL https://ollama.com/install.sh | sh
echo -e "${GREEN}✓ Ollama installed${NC}"
echo ""

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}Step 4: Download AI Model${NC}"
echo -e "${BLUE}==================================${NC}"
echo "Downloading qwen2.5:7b (4.7GB, may take 5-10 minutes)..."
ollama pull qwen2.5:7b
echo -e "${GREEN}✓ Model downloaded${NC}"
echo ""

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}Step 5: Create Custom Model${NC}"
echo -e "${BLUE}==================================${NC}"

# Create Modelfile for weather assistant
cat > /tmp/weatherfile << 'ENDMODEL'
FROM qwen2.5:7b

PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40

SYSTEM """You are a helpful weather assistant. You have access to real-time weather data through your tools. 

When users ask about weather:
- Use get_current_weather for current conditions
- Use get_weather_forecast for multi-day forecasts
- Use compare_weather to compare two cities
- Use get_weather_alerts for weather warnings

Be conversational and helpful. Provide temperature in Celsius by default, but mention Fahrenheit if asked.
"""
ENDMODEL

ollama create weather-assistant -f /tmp/weatherfile
rm /tmp/weatherfile
echo -e "${GREEN}✓ Weather assistant model created${NC}"
echo ""

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}Step 6: Install Open WebUI${NC}"
echo -e "${BLUE}==================================${NC}"

# Create docker network for Ollama if it doesn't exist
docker network create ollama-network 2>/dev/null || true

# Stop and remove existing container if any
docker stop open-webui 2>/dev/null || true
docker rm open-webui 2>/dev/null || true

# Run Open WebUI with proper Ollama connection
docker run -d \
  --name open-webui \
  --network ollama-network \
  -p 3000:8080 \
  -v open-webui:/app/backend/data \
  --add-host=host.docker.internal:host-gateway \
  -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
  -e WEBUI_AUTH=false \
  --restart always \
  ghcr.io/open-webui/open-webui:main

echo "Waiting for Open WebUI to start..."
sleep 10
echo -e "${GREEN}✓ Open WebUI installed${NC}"
echo ""

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}Step 7: Install Python Dependencies${NC}"
echo -e "${BLUE}==================================${NC}"
sudo apt install -y python3-pip python3-venv
echo -e "${GREEN}✓ Python dependencies installed${NC}"
echo ""

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}Step 8: Create Weather MCP Server${NC}"
echo -e "${BLUE}==================================${NC}"

# Create directory for MCP server
mkdir -p ~/weather-tools
cd ~/weather-tools

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install --quiet fastmcp httpx

# Create weather MCP server
cat > weather_mcp_server.py << 'ENDPYTHON'
#!/usr/bin/env python3
"""
MCP Server for Weather Tools
Uses OpenWeatherMap API (Free tier: 1000 calls/day, 60 calls/minute)
"""

import json
import httpx
import os
from typing import Any, Dict
from fastmcp import FastMCP

# Initialize MCP server
mcp = FastMCP("weather-tools")

# OpenWeatherMap API Configuration
OPENWEATHER_API_KEY = os.environ.get("OPENWEATHER_API_KEY", "")
OPENWEATHER_BASE_URL = "https://api.openweathermap.org/data/2.5"

@mcp.tool()
async def get_current_weather(city: str, country_code: str = "") -> Dict[str, Any]:
    """
    Get current weather for a city.
    
    Args:
        city: City name (e.g., 'London', 'New York', 'Tokyo')
        country_code: Optional 2-letter country code (e.g., 'US', 'GB', 'JP')
    
    Returns:
        Current weather including temperature, conditions, humidity, wind
    """
    try:
        # Build location query
        location = f"{city},{country_code}" if country_code else city
        
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{OPENWEATHER_BASE_URL}/weather",
                params={
                    "q": location,
                    "appid": OPENWEATHER_API_KEY,
                    "units": "metric"
                },
                timeout=10.0
            )
            response.raise_for_status()
            data = response.json()
            
            return {
                "success": True,
                "location": {
                    "city": data["name"],
                    "country": data["sys"]["country"],
                    "coordinates": {
                        "lat": data["coord"]["lat"],
                        "lon": data["coord"]["lon"]
                    }
                },
                "weather": {
                    "condition": data["weather"][0]["main"],
                    "description": data["weather"][0]["description"],
                    "temperature": {
                        "current": round(data["main"]["temp"], 1),
                        "feels_like": round(data["main"]["feels_like"], 1),
                        "min": round(data["main"]["temp_min"], 1),
                        "max": round(data["main"]["temp_max"], 1)
                    },
                    "humidity": data["main"]["humidity"],
                    "pressure": data["main"]["pressure"],
                    "visibility": data.get("visibility", 0) / 1000,  # Convert to km
                    "wind": {
                        "speed": data["wind"]["speed"],
                        "direction": data["wind"].get("deg", 0)
                    },
                    "clouds": data["clouds"]["all"]
                },
                "timestamp": data["dt"]
            }
    except httpx.HTTPStatusError as e:
        if e.response.status_code == 404:
            return {
                "success": False,
                "error": f"City '{city}' not found. Try adding country code (e.g., 'London,GB')"
            }
        elif e.response.status_code == 401:
            return {
                "success": False,
                "error": "Invalid API key. Please check your OpenWeatherMap API key."
            }
        else:
            return {
                "success": False,
                "error": f"API error: {e.response.status_code}"
            }
    except Exception as e:
        return {
            "success": False,
            "error": f"Error fetching weather: {str(e)}"
        }

@mcp.tool()
async def get_weather_forecast(city: str, country_code: str = "", days: int = 3) -> Dict[str, Any]:
    """
    Get weather forecast for the next few days.
    
    Args:
        city: City name (e.g., 'London', 'New York', 'Tokyo')
        country_code: Optional 2-letter country code (e.g., 'US', 'GB', 'JP')
        days: Number of days forecast (1-5, default 3)
    
    Returns:
        Weather forecast for specified number of days
    """
    try:
        # Build location query
        location = f"{city},{country_code}" if country_code else city
        
        # Limit days to 5 (free tier limitation)
        days = min(max(days, 1), 5)
        cnt = days * 8  # API returns 3-hour intervals, 8 per day
        
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{OPENWEATHER_BASE_URL}/forecast",
                params={
                    "q": location,
                    "appid": OPENWEATHER_API_KEY,
                    "units": "metric",
                    "cnt": cnt
                },
                timeout=10.0
            )
            response.raise_for_status()
            data = response.json()
            
            # Group forecasts by day
            daily_forecasts = {}
            for item in data["list"]:
                date = item["dt_txt"].split(" ")[0]
                if date not in daily_forecasts:
                    daily_forecasts[date] = {
                        "date": date,
                        "temperatures": [],
                        "conditions": [],
                        "humidity": [],
                        "forecasts": []
                    }
                
                daily_forecasts[date]["temperatures"].append(item["main"]["temp"])
                daily_forecasts[date]["conditions"].append(item["weather"][0]["description"])
                daily_forecasts[date]["humidity"].append(item["main"]["humidity"])
                daily_forecasts[date]["forecasts"].append({
                    "time": item["dt_txt"],
                    "temp": item["main"]["temp"],
                    "condition": item["weather"][0]["description"]
                })
            
            # Calculate daily summaries
            summaries = []
            for date, info in list(daily_forecasts.items())[:days]:
                summaries.append({
                    "date": date,
                    "temp_min": round(min(info["temperatures"]), 1),
                    "temp_max": round(max(info["temperatures"]), 1),
                    "temp_avg": round(sum(info["temperatures"]) / len(info["temperatures"]), 1),
                    "avg_humidity": round(sum(info["humidity"]) / len(info["humidity"])),
                    "common_condition": max(set(info["conditions"]), key=info["conditions"].count),
                    "hourly_forecasts": info["forecasts"]
                })
            
            return {
                "success": True,
                "location": {
                    "city": data["city"]["name"],
                    "country": data["city"]["country"]
                },
                "forecast_days": days,
                "daily_forecast": summaries
            }
    except Exception as e:
        return {
            "success": False,
            "error": f"Error fetching forecast: {str(e)}"
        }

@mcp.tool()
async def compare_weather(city1: str, city2: str) -> Dict[str, Any]:
    """
    Compare current weather between two cities.
    
    Args:
        city1: First city name
        city2: Second city name
    
    Returns:
        Weather comparison between the two cities
    """
    try:
        # Get weather for both cities
        weather1 = await get_current_weather(city1)
        weather2 = await get_current_weather(city2)
        
        if not weather1.get("success") or not weather2.get("success"):
            return {
                "success": False,
                "error": "Could not fetch weather for one or both cities",
                "city1_status": weather1.get("success", False),
                "city2_status": weather2.get("success", False)
            }
        
        # Calculate differences
        temp_diff = abs(
            weather1["weather"]["temperature"]["current"] - 
            weather2["weather"]["temperature"]["current"]
        )
        
        return {
            "success": True,
            "comparison": {
                "city1": {
                    "name": weather1["location"]["city"],
                    "temperature": weather1["weather"]["temperature"]["current"],
                    "condition": weather1["weather"]["description"],
                    "humidity": weather1["weather"]["humidity"]
                },
                "city2": {
                    "name": weather2["location"]["city"],
                    "temperature": weather2["weather"]["temperature"]["current"],
                    "condition": weather2["weather"]["description"],
                    "humidity": weather2["weather"]["humidity"]
                },
                "differences": {
                    "temperature_diff": round(temp_diff, 1),
                    "warmer_city": weather1["location"]["city"] if weather1["weather"]["temperature"]["current"] > weather2["weather"]["temperature"]["current"] else weather2["location"]["city"]
                }
            }
        }
    except Exception as e:
        return {
            "success": False,
            "error": f"Error comparing weather: {str(e)}"
        }

@mcp.tool()
async def get_weather_alerts(city: str, country_code: str = "") -> Dict[str, Any]:
    """
    Check for weather alerts and recommendations.
    
    Args:
        city: City name
        country_code: Optional 2-letter country code
    
    Returns:
        Weather-based alerts and recommendations
    """
    try:
        weather = await get_current_weather(city, country_code)
        
        if not weather.get("success"):
            return weather
        
        alerts = []
        recommendations = []
        
        temp = weather["weather"]["temperature"]["current"]
        condition = weather["weather"]["condition"].lower()
        humidity = weather["weather"]["humidity"]
        wind_speed = weather["weather"]["wind"]["speed"]
        
        # Temperature alerts
        if temp > 35:
            alerts.append("⚠️ Extreme heat warning")
            recommendations.append("Stay hydrated and avoid outdoor activities")
        elif temp > 30:
            alerts.append("🌡️ High temperature")
            recommendations.append("Drink plenty of water")
        elif temp < 0:
            alerts.append("❄️ Freezing conditions")
            recommendations.append("Dress warmly and be careful of ice")
        elif temp < 10:
            alerts.append("🧥 Cold weather")
            recommendations.append("Wear warm clothing")
        
        # Weather condition alerts
        if "rain" in condition or "drizzle" in condition:
            alerts.append("🌧️ Rain expected")
            recommendations.append("Bring an umbrella")
        elif "snow" in condition:
            alerts.append("🌨️ Snow expected")
            recommendations.append("Drive carefully and dress warmly")
        elif "storm" in condition or "thunderstorm" in condition:
            alerts.append("⛈️ Thunderstorm warning")
            recommendations.append("Stay indoors if possible")
        
        # Wind alerts
        if wind_speed > 15:
            alerts.append("💨 Strong winds")
            recommendations.append("Secure loose objects outside")
        
        # Humidity alerts
        if humidity > 80:
            alerts.append("💧 High humidity")
            recommendations.append("May feel uncomfortable; stay cool")
        
        if not alerts:
            alerts.append("✅ No significant weather alerts")
            recommendations.append("Good weather conditions")
        
        return {
            "success": True,
            "location": weather["location"],
            "current_conditions": {
                "temperature": temp,
                "condition": weather["weather"]["description"],
                "humidity": humidity,
                "wind_speed": wind_speed
            },
            "alerts": alerts,
            "recommendations": recommendations
        }
    except Exception as e:
        return {
            "success": False,
            "error": f"Error getting alerts: {str(e)}"
        }

if __name__ == "__main__":
    mcp.run()
ENDPYTHON

chmod +x weather_mcp_server.py

# Create systemd service
sudo tee /etc/systemd/system/weather-mcp.service > /dev/null << ENDSERVICE
[Unit]
Description=Weather MCP Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/weather-tools
Environment="OPENWEATHER_API_KEY=$OPENWEATHER_API_KEY"
ExecStart=$HOME/weather-tools/venv/bin/python $HOME/weather-tools/weather_mcp_server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
ENDSERVICE

# Start and enable service
sudo systemctl daemon-reload
sudo systemctl enable weather-mcp.service
sudo systemctl start weather-mcp.service

deactivate
echo -e "${GREEN}✓ Weather MCP server created and started${NC}"
echo ""

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}Step 9: Configure Nginx${NC}"
echo -e "${BLUE}==================================${NC}"
sudo apt install -y nginx

# Configure Nginx
sudo tee /etc/nginx/sites-available/default > /dev/null << 'ENDNGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket support for Open WebUI
    location /ws {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
ENDNGINX

sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

echo -e "${GREEN}✓ Nginx configured${NC}"
echo ""

# Get public IP
PUBLIC_IP=$(curl -s ifconfig.me)

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      ✨ Installation Complete! ✨            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Access your Weather AI Assistant at:${NC}"
echo -e "${YELLOW}  http://$PUBLIC_IP${NC}"
echo ""
echo -e "${BLUE}Available Tools:${NC}"
echo "  • get_current_weather - Current weather for any city"
echo "  • get_weather_forecast - 5-day forecast"
echo "  • compare_weather - Compare two cities"
echo "  • get_weather_alerts - Weather warnings & tips"
echo ""
echo -e "${BLUE}Example Questions:${NC}"
echo "  • What's the weather in Paris?"
echo "  • Give me a 5-day forecast for Tokyo"
echo "  • Compare weather in London and New York"
echo "  • Are there any weather alerts for Miami?"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "  Check MCP Server:  sudo systemctl status weather-mcp"
echo "  Check Ollama:      ollama list"
echo "  Check Docker:      docker ps"
echo "  View MCP Logs:     sudo journalctl -u weather-mcp -f"
echo ""
echo -e "${GREEN}🎉 Enjoy your AI Weather Assistant!${NC}"
echo ""
