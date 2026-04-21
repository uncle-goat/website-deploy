# 静态站点托管指南

## 何时使用静态托管

静态托管适用于以下场景：

- 纯 HTML/CSS/JavaScript 网站或落地页
- 使用 Vite、Create React App、Next.js 静态导出等构建的 SPA（单页应用）
- 静态站点生成器构建的博客或文档站（Hugo、Jekyll、Astro、Gatsby）
- 无需服务端渲染（SSR）或后端 API 的项目

> 如果项目需要 SSR、API 路由或数据库，应选择 Vercel、Netlify 或云服务器等方案。

---

## Cloudflare Pages

### 优势

- **全球 CDN**：自动分发到 Cloudflare 全球节点，访问速度快
- **自动 SSL**：免费提供 SSL 证书，无需手动配置
- **无限带宽**：不限制流量，适合高访问量站点
- **预览部署**：每个 Pull Request 自动生成预览 URL，方便团队协作
- **Web Analytics**：内置免费隐私友好的网站分析

### 部署方式

#### 方式一：连接 Git 仓库（推荐）

1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)，进入 Pages
2. 点击「创建项目」->「连接到 Git」
3. 选择 GitHub 或 GitLab 仓库
4. 配置构建设置：
   - **构建命令**：`npm run build`
   - **构建输出目录**：`dist`（根据框架调整）
   - **Node.js 版本**：`18`（或项目所需版本）
5. 点击「保存并部署」，推送代码后自动触发构建

#### 方式二：Wrangler CLI 手动部署

```bash
# 安装 Wrangler
npm install -g wrangler

# 登录 Cloudflare 账号
wrangler login

# 部署指定目录
npx wrangler pages deploy ./dist --project-name=my-site
```

适合不使用 Git 仓库或需要 CI/CD 自定义流程的场景。

### 自定义域名

1. 在 Pages 项目设置中点击「自定义域」->「添加域」
2. 输入域名（如 `www.example.com`）
3. 根据提示配置 DNS 记录：
   - 如果域名已托管在 Cloudflare：自动添加 CNAME 记录
   - 如果域名在其他 DNS 服务商：手动添加 CNAME 记录指向 `<project>.pages.dev`

### SPA 路由配置

SPA 使用前端路由（如 React Router、Vue Router）时，需要将所有路径重定向到 `index.html`。

在构建输出目录中创建 `_redirects` 文件：

```
/* /index.html 200
```

或在 `public/` 目录中创建（确保构建时会被复制到输出目录）。

### 环境变量

在 Pages Dashboard -> 项目设置 -> 环境变量中配置：

- **Production**：生产环境变量
- **Preview**：预览环境变量（PR 预览部署时使用）

构建时通过 `process.env.VARIABLE_NAME` 访问（Vite 需以 `VITE_` 为前缀）。

---

## GitHub Pages

### 优势

- **免费**：对公开仓库完全免费
- **GitHub 集成**：与 GitHub 仓库深度整合，操作简便
- **适合开源项目**：文档站、项目主页的理想选择

### 限制

- 仅支持静态内容，不支持服务端逻辑
- 仓库大小限制 1GB，推荐站点不超过 1GB
- 自定义域名需要在仓库根目录放置 `CNAME` 文件
- 不支持 SPA 路由（需要 404.html 变通方案）
- 带宽有限（每月 100GB 软限制）

### 使用 GitHub Actions 部署

推荐使用 GitHub Actions 实现自动构建和部署。参考模板文件 `templates/github-actions-deploy.yml`。

基本流程：

1. 推送代码到仓库
2. GitHub Actions 自动触发构建
3. 构建产物部署到 `gh-pages` 分支
4. GitHub Pages 从该分支提供服务

```yaml
# .github/workflows/deploy.yml 基本结构
name: Deploy to GitHub Pages
on:
  push:
    branches: [main]
permissions:
  contents: read
  pages: write
  id-token: write
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npm run build
      - uses: actions/upload-pages-artifact@v3
        with:
          path: ./dist
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/deploy-pages@v4
        id: deployment
```

### 自定义域名

1. 在仓库根目录创建 `CNAME` 文件，写入域名：
   ```
   www.example.com
   ```
2. 在 GitHub 仓库 Settings -> Pages -> Custom domain 中填入域名
3. 在 DNS 服务商配置记录：
   - `CNAME` 记录：`www` 指向 `<username>.github.io`
   - 如使用裸域名（`example.com`）：添加 `A` 记录指向 GitHub Pages IP

---

## Cloudflare Pages vs GitHub Pages 如何选择

| 对比项 | Cloudflare Pages | GitHub Pages |
|--------|-----------------|--------------|
| **性能** | 全球 CDN，速度快 | 单节点，海外访问较慢 |
| **带宽** | 无限制 | 每月约 100GB |
| **自定义域名** | 简单，自动配置 | 需手动配置 DNS 和 CNAME |
| **SPA 支持** | 原生支持（_redirects） | 需 404.html 变通 |
| **预览部署** | 每个 PR 自动生成 | 不支持 |
| **构建限制** | 无硬性限制 | 仓库 1GB |
| **适合场景** | 生产站点、高流量 | 开源文档、个人项目 |

**建议**：生产环境优先选择 Cloudflare Pages；GitHub 生态内的开源项目文档可使用 GitHub Pages。

---

## 各框架构建输出目录参考

| 框架 / 工具 | 构建命令 | 输出目录 |
|------------|---------|---------|
| Vite | `npm run build` | `dist/` |
| Create React App | `npm run build` | `build/` |
| Next.js（静态导出） | `next build && next export` | `out/` |
| Hugo | `hugo` | `public/` |
| Jekyll | `jekyll build` | `_site/` |
| Astro | `npm run build` | `dist/` |
| Gatsby | `npm run build` | `public/` |
| Nuxt（静态生成） | `npm run generate` | `dist/` |
| Vue CLI | `npm run build` | `dist/` |

> 在配置 Cloudflare Pages 或 GitHub Actions 时，请根据上表填写正确的构建输出目录。
