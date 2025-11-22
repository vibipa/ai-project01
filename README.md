# ai-project01
# Flight AI Assistant - Web Portal

A modern web application that combines **Ollama** (local LLM), **MCP (Model Context Protocol)**, and real-time flight tracking into an intelligent AI assistant portal.

## 🌟 Features

- **AI-Powered Chat Interface**: Natural language interaction with flight data
- **Real-Time Flight Tracking**: Monitor multiple flights simultaneously
- **Autonomous Agent**: AI automatically decides which tools to use
- **Flight Status API Integration**: Live data from aviationstack.com
- **Persistent Tracking**: SQLite database for saved flights
- **WebSocket Updates**: Real-time notifications for flight changes
- **Modern UI**: Responsive React interface with beautiful animations

## 🏗️ Architecture

```
┌─────────────────┐      ┌──────────────────┐      ┌────────────────┐
│  React Frontend │ ←──→ │  FastAPI Backend │ ←──→ │ Ollama (Local) │
│  (Port 3000)    │      │  (Port 8000)     │      │ (Port 11434)   │
└─────────────────┘      └──────────────────┘      └────────────────┘
         │                        │
         │                        ↓
         │               ┌──────────────────┐
         └──────────────→│  Flight Status   │
                         │  API (External)  │
                         └──────────────────┘
```

## 📋 Prerequisites

Before starting, install:

1. **Python 3.10+** - [Download](https://www.python.org/downloads/)
2. **Node.js 18+** - [Download](https://nodejs.org/)
3. **Ollama** - [Download](https://ollama.ai)

## 🚀 Quick Start

### Step 1: Install Ollama and Pull Model

```bash
# Install Ollama (visit ollama.ai for your OS)

# Start Ollama service
ollama serve

# In a new terminal, pull a model with tool-calling
ollama pull qwen2.5:7b
```

### Step 2: Get Flight API Key

1. Visit [aviationstack.com](https://aviationstack.com)
2. Sign up for free account (100 requests/month)
3. Copy your API key

### Step 3: Setup Backend

```bash
cd backend

# Create virtual environment
python -m venv venv

# Activate it
# On macOS/Linux:
source venv/bin/activate
# On Windows:
venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Edit main.py and add your API key
# Replace: AVIATION_API_KEY = "your_api_key_here"
```

### Step 4: Setup Frontend

```bash
cd frontend

# Install dependencies
npm install
```

### Step 5: Run the Application

**Terminal 1 - Ollama (if not already running):**
```bash
ollama serve
```

**Terminal 2 - Backend:**
```bash
cd backend
source venv/bin/activate  # or venv\Scripts\activate on Windows
python main.py
```

**Terminal 3 - Frontend:**
```bash
cd frontend
npm run dev
```

### Step 6: Access the Portal

Open your browser to: **http://localhost:3000**

## 🎮 How to Use

### Chat Interface

Ask natural language questions:
- "What's the status of flight AA100?"
- "Is flight BA123 delayed?"
- "Show me information about United 789"
- "Track flight DL456 for me"

The AI will:
1. Understand your question
2. Automatically call the flight status API
3. Parse and present the information naturally
4. Offer to track flights you inquire about

### Tracked Flights

1. Click **"Tracked Flights"** tab
2. View all monitored flights
3. Click **"View Details"** for comprehensive information
4. Click **trash icon** to stop tracking
5. **Auto-updates every 5 minutes** via WebSocket

### Flight Details

Comprehensive view showing:
- Departure airport, terminal, gate
- Arrival airport, terminal, gate
- Scheduled vs. actual times
- Flight status (active, delayed, landed, etc.)
- Aircraft registration

## 🔧 Configuration

### Backend Settings (main.py)

```python
# Ollama configuration
OLLAMA_BASE_URL = "http://localhost:11434"

# Aviation API
AVIATION_API_KEY = "your_api_key_here"
AVIATION_BASE_URL = "http://api.aviationstack.com/v1"

# Update frequency (seconds)
TRACKING_UPDATE_INTERVAL = 300  # 5 minutes
```

### Frontend Settings (App.jsx)

```javascript
const API_BASE = 'http://localhost:8000';
```

### Ollama Model Selection

Edit `main.py` to change the model:
```python
"model": "qwen2.5:7b"  # Change to: llama3.2:3b, mistral:7b, etc.
```

**Supported models with tool-calling:**
- qwen2.5 (recommended)
- llama3.2
- mistral
- mixtral
- command-r

## 📁 Project Structure

```
flight-portal/
├── backend/
│   ├── main.py              # FastAPI server + Ollama integration
│   ├── requirements.txt     # Python dependencies
│   └── flights.db          # SQLite database (auto-created)
├── frontend/
│   ├── src/
│   │   ├── App.jsx         # Main React component
│   │   ├── App.css         # Styles
│   │   └── main.jsx        # Entry point
│   ├── package.json        # Node dependencies
│   ├── vite.config.js      # Vite configuration
│   └── index.html          # HTML template
└── README.md               # This file
```

## 🎯 API Endpoints

### Backend REST API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/chat` | POST | Chat with AI agent |
| `/api/flight/{number}` | GET | Get flight status |
| `/api/track` | POST | Track a flight |
| `/api/tracked` | GET | List tracked flights |
| `/api/track/{number}` | DELETE | Untrack flight |
| `/ws` | WebSocket | Real-time updates |

### Example API Usage

**Chat with AI:**
```bash
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What is the status of flight AA100?",
    "conversation_history": []
  }'
```

**Get Flight Status:**
```bash
curl http://localhost:8000/api/flight/AA100
```

**Track Flight:**
```bash
curl -X POST http://localhost:8000/api/track \
  -H "Content-Type: application/json" \
  -d '{
    "flight_number": "AA100",
    "notes": "My flight home"
  }'
```

## 🔍 How MCP Works in This Project

This project demonstrates **Model Context Protocol (MCP)** principles:

1. **Tools Definition**: Flight lookup functions are defined as callable tools
2. **Autonomous Decision**: AI decides when to call tools based on user intent
3. **Tool Execution**: Backend executes the selected tool with extracted parameters
4. **Result Integration**: Tool results are fed back to AI for natural response
5. **Context Preservation**: Conversation history maintained for coherent dialogue

The AI acts as an **agent**, not just a chatbot:
- Understands user intent
- Selects appropriate tools
- Executes multi-step tasks
- Provides contextual responses

## 🛠️ Troubleshooting

### "Connection refused to Ollama"
```bash
# Make sure Ollama is running:
ollama serve

# Test it:
ollama run qwen2.5:7b "Hello"
```

### "Model doesn't support tools"
```bash
# Only certain models support tool-calling
# Switch to a supported model:
ollama pull qwen2.5:7b
```

### "API rate limit exceeded"
- Free tier: 100 requests/month
- Consider caching or upgrading plan
- Check your usage at aviationstack.com

### "WebSocket connection failed"
- Ensure backend is running on port 8000
- Check CORS settings in main.py
- Verify firewall isn't blocking WebSocket

### "Frontend can't connect to backend"
```bash
# Check backend is running:
curl http://localhost:8000

# Check CORS configuration in main.py allows localhost:3000
```

### Database Issues
```bash
# Reset database:
rm backend/flights.db
# It will be recreated on next startup
```

## 🚀 Enhancements & Ideas

### Add More Tools

```python
@app.get("/api/airport/{iata_code}")
async def get_airport_info(iata_code: str):
    """Get airport information"""
    # Implement airport lookup
    pass

@app.get("/api/airline/{code}")
async def get_airline_info(code: str):
    """Get airline information"""
    # Implement airline lookup
    pass
```

### Add Notifications

```python
# Email alerts when flights are delayed
# SMS notifications via Twilio
# Push notifications via Firebase
```

### Add Authentication

```python
from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer

# Implement user authentication
# Multi-user flight tracking
```

### Deploy to Production

```bash
# Use Docker for easy deployment:
# Create Dockerfile for backend
# Create Dockerfile for frontend
# Use docker-compose for orchestration
```

### Add More Data Sources

- Weather data (OpenWeatherMap API)
- Airport delays (FAA API)
- Flight prices (Skyscanner API)
- Hotel availability near airports

## 📚 Learning Outcomes

This project teaches you:

✅ **Local LLM Integration** - Running AI models locally with Ollama
✅ **MCP Concepts** - Tool-calling and autonomous agents
✅ **Full-Stack Development** - React + FastAPI integration
✅ **Real-Time Communication** - WebSocket implementation
✅ **Database Management** - SQLite for persistence
✅ **API Integration** - External API consumption
✅ **Modern UI/UX** - Responsive design patterns
✅ **Async Programming** - Python async/await patterns

## 🤝 Contributing

This is a learning project! Feel free to:
- Add new features
- Improve the UI
- Add more MCP tools
- Optimize performance
- Write tests

## 📄 License

MIT License - Feel free to use this for learning and building!

## 🆘 Support

Having issues? Here's how to get help:

1. Check the troubleshooting section above
2. Verify all prerequisites are installed
3. Ensure Ollama is running with a tool-capable model
4. Check API key is valid and has remaining quota
5. Look for error messages in browser console and terminal

## 🎓 Next Steps

Now that you have a working portal:

1. **Experiment**: Try different prompts and see how the AI responds
2. **Extend**: Add new tools and capabilities
3. **Learn**: Study how MCP enables tool-calling
4. **Build**: Create your own AI agent for a different domain
5. **Share**: Show others what you've built!

---

**Happy Building! ✈️🤖**
