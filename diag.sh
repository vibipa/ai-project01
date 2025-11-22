cat > full-diagnostic.sh << 'EOF'
#!/bin/bash

echo "=========================================="
echo "1. OLLAMA BINARY CHECK"
echo "=========================================="
which ollama
file /usr/local/bin/ollama 2>/dev/null || echo "Binary not found"
/usr/local/bin/ollama --version 2>&1 || echo "Can't run ollama"
echo ""

echo "=========================================="
echo "2. OLLAMA SERVICE STATUS"
echo "=========================================="
sudo systemctl status ollama --no-pager 2>&1
echo ""

echo "=========================================="
echo "3. OLLAMA SERVICE FILE"
echo "=========================================="
cat /etc/systemd/system/ollama.service 2>/dev/null || echo "Service file not found"
echo ""

echo "=========================================="
echo "4. PORTS LISTENING"
echo "=========================================="
sudo netstat -tlnp | grep -E '(11434|3000|80)'
echo ""

echo "=========================================="
echo "5. OLLAMA PROCESSES"
echo "=========================================="
ps aux | grep ollama | grep -v grep
echo ""

echo "=========================================="
echo "6. OLLAMA LOGS (if service exists)"
echo "=========================================="
sudo journalctl -u ollama -n 50 --no-pager 2>/dev/null || echo "No service logs"
echo ""

echo "=========================================="
echo "7. TRY RUNNING OLLAMA MANUALLY"
echo "=========================================="
timeout 5 ollama serve 2>&1 || echo "Failed to run ollama serve"
echo ""

echo "=========================================="
echo "8. SYSTEM RESOURCES"
echo "=========================================="
free -h
df -h /
echo ""

echo "=========================================="
echo "9. DOCKER STATUS"
echo "=========================================="
docker ps -a
echo ""

echo "============================
