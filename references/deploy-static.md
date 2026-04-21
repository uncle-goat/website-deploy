# Static Site Hosting Guide

## When to Use Static Hosting

Static hosting is suitable for the following scenarios:

- Pure HTML/CSS/JavaScript websites or landing pages
- SPAs (Single Page Applications) built with Vite, Create React App, Next.js static export, etc.
- Blogs or documentation sites built with static site generators (Hugo, Jekyll, Astro, Gatsby)
- Projects that do not require server-side rendering (SSR) or a backend API

> If the project requires SSR, API routes, or a database, consider solutions like Vercel, Netlify, or cloud servers.

---

## Cloudflare Pages

### Advantages

- **Global CDN:** Automatically distributed to Cloudflare's global nodes for fast access
- **Automatic SSL:** Free SSL certificates provided, no manual configuration needed
- **Unlimited bandwidth:** No traffic limits, suitable for high-traffic sites
- **Preview deployments:** Each Pull Request automatically generates a preview URL for team collaboration
- **Web Analytics:** Built-in, free, privacy-friendly website analytics

### Deployment Methods

#### Method 1: Connect a Git Repository (Recommended)

1. Log in to the [Cloudflare Dashboard](https://dash.cloudflare.com/) and go to Pages
2. Click "Create a project" -> "Connect to Git"
3. Select a GitHub or GitLab repository
4. Configure build settings:
   - **Build command:** `npm run build`
   - **Build output directory:** `dist` (adjust based on the framework)
   - **Node.js version:** `18` (or the version required by the project)
5. Click "Save and Deploy"; pushing code will automatically trigger a build

#### Method 2: Wrangler CLI Manual Deployment

```bash
# Install Wrangler
npm install -g wrangler

# Log in to your Cloudflare account
wrangler login

# Deploy a specific directory
npx wrangler pages deploy ./dist --project-name=my-site
```

Suitable for scenarios without a Git repository or when custom CI/CD workflows are needed.

### Custom Domain

1. In the Pages project settings, click "Custom domains" -> "Add domain"
2. Enter the domain (e.g., `www.example.com`)
3. Configure DNS records as prompted:
   - If the domain is already hosted on Cloudflare: a CNAME record is added automatically
   - If the domain is with another DNS provider: manually add a CNAME record pointing to `<project>.pages.dev`

### SPA Routing Configuration

When an SPA uses client-side routing (such as React Router or Vue Router), all paths need to be redirected to `index.html`.

Create a `_redirects` file in the build output directory:

```
/* /index.html 200
```

Or create it in the `public/` directory (ensure it gets copied to the output directory during the build).

### Environment Variables

Configure in Pages Dashboard -> Project settings -> Environment variables:

- **Production:** Production environment variables
- **Preview:** Preview environment variables (used for PR preview deployments)

Access during build time via `process.env.VARIABLE_NAME` (Vite requires the `VITE_` prefix).

---

## GitHub Pages

### Advantages

- **Free:** Completely free for public repositories
- **GitHub integration:** Deeply integrated with GitHub repositories, easy to use
- **Ideal for open source projects:** A great choice for documentation sites and project homepages

### Limitations

- Only supports static content; no server-side logic
- Repository size limit of 1GB; recommended site size under 1GB
- Custom domains require a `CNAME` file in the repository root
- No native SPA routing support (requires a 404.html workaround)
- Limited bandwidth (soft limit of 100GB per month)

### Deploying with GitHub Actions

Using GitHub Actions is recommended for automated builds and deployments. See the template file `templates/github-actions-deploy.yml`.

Basic workflow:

1. Push code to the repository
2. GitHub Actions automatically triggers a build
3. Build artifacts are deployed to the `gh-pages` branch
4. GitHub Pages serves the site from that branch

```yaml
# .github/workflows/deploy.yml basic structure
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

### Custom Domain

1. Create a `CNAME` file in the repository root with the domain:
   ```
   www.example.com
   ```
2. Enter the domain in GitHub repository Settings -> Pages -> Custom domain
3. Configure records with your DNS provider:
   - `CNAME` record: `www` pointing to `<username>.github.io`
   - If using a bare domain (`example.com`): add an `A` record pointing to GitHub Pages IP addresses

---

## Cloudflare Pages vs GitHub Pages: How to Choose

| Comparison | Cloudflare Pages | GitHub Pages |
|------------|-----------------|--------------|
| **Performance** | Global CDN, fast | Single node, slower for international access |
| **Bandwidth** | Unlimited | Approximately 100GB per month |
| **Custom domain** | Simple, auto-configured | Requires manual DNS and CNAME configuration |
| **SPA support** | Native support (_redirects) | Requires 404.html workaround |
| **Preview deployments** | Auto-generated per PR | Not supported |
| **Build limits** | No hard limits | 1GB repository limit |
| **Best for** | Production sites, high traffic | Open source docs, personal projects |

**Recommendation:** For production environments, prefer Cloudflare Pages; for open source project documentation within the GitHub ecosystem, GitHub Pages is a good choice.

---

## Build Output Directory Reference by Framework

| Framework / Tool | Build Command | Output Directory |
|------------------|---------------|------------------|
| Vite | `npm run build` | `dist/` |
| Create React App | `npm run build` | `build/` |
| Next.js (static export) | `next build && next export` | `out/` |
| Hugo | `hugo` | `public/` |
| Jekyll | `jekyll build` | `_site/` |
| Astro | `npm run build` | `dist/` |
| Gatsby | `npm run build` | `public/` |
| Nuxt (static generation) | `npm run generate` | `dist/` |
| Vue CLI | `npm run build` | `dist/` |

> When configuring Cloudflare Pages or GitHub Actions, please refer to the table above to enter the correct build output directory.
