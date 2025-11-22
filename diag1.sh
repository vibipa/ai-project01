# 1. Check current models
echo "=== Current Models ==="
ollama list

# 2. Pull qwen2.5:7b if not present
echo "=== Pulling Model (this takes 5-10 min) ==="
ollama pull qwen2.5:7b

# 3. Verify model is there
echo "=== Verifying Model ==="
ollama list

# 4. Check API returns the model
echo "=== API Check ==="
curl http://127.0.0.1:11434/api/tags | python3 -m json.tool

# 5. Restart Open WebUI to pick up the model
echo "=== Restarting Open WebUI ==="
docker restart open-webui
sleep 15

# 6. Test from inside container
echo "=== Testing from Container ==="
docker exec open-webui curl -s http://127.0.0.1:11434/api/tags | python3 -m json.tool

echo ""
echo "=== DONE ==="
echo "Open your browser to: http://$(curl -s ifconfig.me):8080"
echo "The model selector should now show: qwen2.5:7b"
