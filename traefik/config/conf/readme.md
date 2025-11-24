# Traefik Dynamic Configuration Directory

This directory is monitored by Traefik for configuration changes in real-time.

## How to Use

1. Create `.yml` or `.yaml` files in this directory
2. Traefik will automatically detect and apply changes (no restart needed)
3. Use these for defining routers, services, and middlewares

## File Naming

- Use descriptive names: `whoami.yml`, `nextcloud.yml`, etc.
- Files must have `.yml` or `.yaml` extension
- Files ending in `.example` are ignored

## Example Structure

```yaml
http:
  routers:
    myapp:
      rule: "Host(\`myapp.example.com\`)"
      entryPoints:
        - websecure
      service: myapp
      tls:
        certResolver: cloudflare
      middlewares:
        - crowdsec-bouncer@file

  services:
    myapp:
      loadBalancer:
        servers:
          - url: "http://myapp-container:8080"

  middlewares:
    crowdsec-bouncer:
      forwardAuth:
        address: http://bouncer-traefik:8080/api/v1/forwardAuth
        trustForwardHeader: true
```

## Testing Configuration

After adding a file, check Traefik logs:
```bash
docker compose logs -f traefik
```

## Common Patterns

### Simple HTTP Service
```yaml
http:
  routers:
    service-name:
      rule: "Host(\`service.domain.com\`)"
      service: service-name
  services:
    service-name:
      loadBalancer:
        servers:
          - url: "http://container:port"
```

### With Authentication
```yaml
http:
  routers:
    secure-app:
      rule: "Host(\`app.domain.com\`)"
      middlewares:
        - auth
        - crowdsec-bouncer@file
      service: secure-app
  
  middlewares:
    auth:
      basicAuth:
        users:
          - "admin:$apr1$..." # Use htpasswd to generate
  
  services:
    secure-app:
      loadBalancer:
        servers:
          - url: "http://app:8080"
```

## Documentation

Full documentation: https://doc.traefik.io/traefik/providers/file/
