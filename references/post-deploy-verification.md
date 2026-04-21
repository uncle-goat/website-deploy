# 部署后验证方案

## 基本验证

**HTTP 状态码检查：**
```bash
# 检查 HTTP 响应（期望 200 或 301/302）
curl -I http://domain

# 检查 HTTPS 响应（期望 200）
curl -I https://domain
```

**页面内容检查：**
```bash
# 验证页面包含预期内容
curl -s https://domain | grep -q "expected text" && echo "OK" || echo "FAIL"
```

**响应时间检查：**
```bash
# 测量响应时间
curl -o /dev/null -s -w '%{time_total}s\n' https://domain
```

---

## SSL 证书验证

**证书有效性检查：**
```bash
# 查看证书有效期
openssl s_client -connect domain:443 -servername domain </dev/null 2>/dev/null | openssl x509 -noout -dates
```

**证书到期天数：**
```bash
# 计算证书剩余天数
expiry=$(echo | openssl s_client -connect domain:443 -servername domain 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
expiry_epoch=$(date -d "$expiry" +%s)
now_epoch=$(date +%s)
echo "Certificate expires in $(( (expiry_epoch - now_epoch) / 86400 )) days"
```

**证书域名匹配：**
```bash
# 检查证书 CN 和 SAN 字段
openssl s_client -connect domain:443 -servername domain </dev/null 2>/dev/null | openssl x509 -noout -subject -ext subjectAltName
```

**协议版本检查：**
```bash
# 检查 TLS 版本（应支持 TLSv1.2 和 TLSv1.3）
openssl s_client -connect domain:443 -servername domain -tls1_2 </dev/null 2>&1 | grep "Protocol"
openssl s_client -connect domain:443 -servername domain -tls1_3 </dev/null 2>&1 | grep "Protocol"
```

---

## 服务状态验证

**Docker 部署：**
```bash
# 查看所有服务状态
docker compose ps

# 查看容器日志
docker compose logs --tail=50 app
```

**systemd 服务：**
```bash
# 查看服务状态
systemctl status servicename

# 查看服务日志
journalctl -u servicename --since "10 min ago" -f
```

**PM2 进程：**
```bash
# 查看进程列表
pm2 list

# 查看日志
pm2 logs api --lines 50
```

**Nginx 验证：**
```bash
# 检查配置语法
nginx -t

# 查看 Nginx 状态
systemctl status nginx
```

---

## 应用层验证

**API 健康检查：**
```bash
curl -s https://domain/api/health | python3 -m json.tool
```

**数据库连接：**
```bash
# 检查应用日志中是否有数据库连接错误
docker compose logs app 2>&1 | grep -i "database\|db\|connection" | tail -20
```

**静态资源验证：**
```bash
# 检查 CSS/JS/图片是否正常加载
curl -I https://domain/static/style.css
curl -I https://domain/static/main.js
```

**功能测试：**
- 测试用户登录流程
- 测试核心 CRUD 操作
- 测试文件上传功能（如适用）
- 测试搜索功能（如适用）

---

## 性能基准

**首次请求时间（冷启动）：**
```bash
# 重启服务后首次请求
curl -o /dev/null -s -w 'Cold start: %{time_total}s\n' https://domain
```

**平均响应时间：**
```bash
# 发送 5 次请求计算平均值
for i in {1..5}; do
  curl -o /dev/null -s -w '%{time_total}\n' https://domain
done | awk '{sum+=$1; count++} END {printf "Average: %.3fs (%d requests)\n", sum/count, count}'
```

**错误日志检查：**
```bash
# 检查最近 5 分钟的错误日志
journalctl -u servicename --since "5 min ago" --priority err
```

---

## 验证报告模板

部署验证完成后，向用户报告以下信息：

```
部署验证报告
============

URL: https://domain
状态: healthy / unhealthy
SSL: 有效，剩余 X 天
响应时间: Xms（平均值）
服务状态: 运行中 / 已停止
注意事项: （如有警告或建议）
```
