# Post-Deploy Verification Plan

## Basic Verification

**HTTP Status Code Check:**
```bash
# Check HTTP response (expect 200 or 301/302)
curl -I http://domain

# Check HTTPS response (expect 200)
curl -I https://domain
```

**Page Content Check:**
```bash
# Verify the page contains expected content
curl -s https://domain | grep -q "expected text" && echo "OK" || echo "FAIL"
```

**Response Time Check:**
```bash
# Measure response time
curl -o /dev/null -s -w '%{time_total}s\n' https://domain
```

---

## SSL Certificate Verification

**Certificate Validity Check:**
```bash
# View certificate validity period
openssl s_client -connect domain:443 -servername domain </dev/null 2>/dev/null | openssl x509 -noout -dates
```

**Certificate Expiry Days:**
```bash
# Calculate remaining days until certificate expiry
expiry=$(echo | openssl s_client -connect domain:443 -servername domain 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
expiry_epoch=$(date -d "$expiry" +%s)
now_epoch=$(date +%s)
echo "Certificate expires in $(( (expiry_epoch - now_epoch) / 86400 )) days"
```

**Certificate Domain Match:**
```bash
# Check certificate CN and SAN fields
openssl s_client -connect domain:443 -servername domain </dev/null 2>/dev/null | openssl x509 -noout -subject -ext subjectAltName
```

**Protocol Version Check:**
```bash
# Check TLS version (should support TLSv1.2 and TLSv1.3)
openssl s_client -connect domain:443 -servername domain -tls1_2 </dev/null 2>&1 | grep "Protocol"
openssl s_client -connect domain:443 -servername domain -tls1_3 </dev/null 2>&1 | grep "Protocol"
```

---

## Service Status Verification

**Docker Deployment:**
```bash
# View all service statuses
docker compose ps

# View container logs
docker compose logs --tail=50 app
```

**systemd Service:**
```bash
# View service status
systemctl status servicename

# View service logs
journalctl -u servicename --since "10 min ago" -f
```

**PM2 Process:**
```bash
# View process list
pm2 list

# View logs
pm2 logs api --lines 50
```

**Nginx Verification:**
```bash
# Check configuration syntax
nginx -t

# View Nginx status
systemctl status nginx
```

---

## Application Layer Verification

**API Health Check:**
```bash
curl -s https://domain/api/health | python3 -m json.tool
```

**Database Connection:**
```bash
# Check application logs for database connection errors
docker compose logs app 2>&1 | grep -i "database\|db\|connection" | tail -20
```

**Static Asset Verification:**
```bash
# Check that CSS/JS/images load correctly
curl -I https://domain/static/style.css
curl -I https://domain/static/main.js
```

**Functional Testing:**
- Test user login flow
- Test core CRUD operations
- Test file upload functionality (if applicable)
- Test search functionality (if applicable)

---

## Performance Benchmarks

**First Request Time (Cold Start):**
```bash
# First request after restarting the service
curl -o /dev/null -s -w 'Cold start: %{time_total}s\n' https://domain
```

**Average Response Time:**
```bash
# Send 5 requests and calculate the average
for i in {1..5}; do
  curl -o /dev/null -s -w '%{time_total}\n' https://domain
done | awk '{sum+=$1; count++} END {printf "Average: %.3fs (%d requests)\n", sum/count, count}'
```

**Error Log Check:**
```bash
# Check error logs from the last 5 minutes
journalctl -u servicename --since "5 min ago" --priority err
```

---

## Verification Report Template

After deployment verification is complete, report the following information to the user:

```
Deployment Verification Report
============

URL: https://domain
Status: healthy / unhealthy
SSL: Valid, X days remaining
Response Time: Xms (average)
Service Status: Running / Stopped
Notes: (Any warnings or recommendations)
```
