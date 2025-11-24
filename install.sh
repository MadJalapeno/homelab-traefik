#!/bin/sh
echo "V 0.1.0 - Grouped Stack Approach"
# colorful output
RED="\e[31m"
CYAN="\e[36m"
GREEN="\e[32m"
YELLOW="\e[33m"
END="\e[0m"

echo "*******"
echo "Checking system requirements"
echo "*******"
echo

# Check if Docker is installed
if ! command -v docker >/dev/null 2>&1; then
    echo "${RED}ERROR: Docker is not installed!${END}"
    echo
    echo "Please install Docker first:"
    echo "  Ubuntu/Debian: curl -fsSL https://get.docker.com | sh"
    echo "  Or visit: https://docs.docker.com/engine/install/"
    echo
    exit 1
else
    DOCKER_VERSION=$(docker --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1)
    echo "${GREEN}✓ Docker installed${END} (version: $DOCKER_VERSION)"
fi

# Check if Docker Compose is available
if ! docker compose version >/dev/null 2>&1; then
    echo "${RED}ERROR: Docker Compose is not available!${END}"
    echo
    echo "Docker Compose (v2) should be included with Docker."
    echo "If you're using an older version, please update Docker:"
    echo "  https://docs.docker.com/engine/install/"
    echo
    exit 1
else
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null)
    echo "${GREEN}✓ Docker Compose installed${END} (version: $COMPOSE_VERSION)"
fi

# Check if Docker daemon is running
if ! docker info >/dev/null 2>&1; then
    echo "${RED}ERROR: Docker daemon is not running!${END}"
    echo
    echo "Please start Docker:"
    echo "  sudo systemctl start docker"
    echo "  sudo systemctl enable docker"
    echo
    exit 1
else
    echo "${GREEN}✓ Docker daemon is running${END}"
fi

# Check if user can run Docker (not required if running as root)
if [ "$(id -u)" -ne 0 ] && ! docker ps >/dev/null 2>&1; then
    echo "${YELLOW}WARNING: Current user cannot run Docker commands${END}"
    echo
    echo "You may need to:"
    echo "  1. Add user to docker group: sudo usermod -aG docker \$USER"
    echo "  2. Log out and back in"
    echo "  3. Or run this script with sudo"
    echo
    echo -n "Continue anyway? (y/N): "
    read continue_anyway
    if [ "$continue_anyway" != "y" ] && [ "$continue_anyway" != "Y" ]; then
        exit 1
    fi
else
    echo "${GREEN}✓ Docker permissions OK${END}"
fi

echo
echo "*******"
echo "Checking ports available"
echo "*******"
echo 

# Check port 80 [http]
if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null ; then
    echo "${RED}Port 80 busy${END}"
    lsof -Pi :80 
    exit 1
else
    echo "${GREEN}Port 80 free${END}"
fi

# Check port 443 [https]
if lsof -Pi :443 -sTCP:LISTEN -t >/dev/null ; then
    echo "${RED}Port 443 busy${END}"
    lsof -Pi :443
    exit 1
else
    echo "${GREEN}Port 443 free${END}"
fi

# Check port 8080 [API]
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null ; then
    echo "${RED}Port 8080 busy${END}"
    lsof -Pi :8080
    exit 1
else
    echo "${GREEN}Port 8080 free${END}"
fi

echo
echo "${GREEN}All ports available!${END}"
echo
echo "${CYAN}Please enter your info${END}"
echo

# Get info for installation
echo -n "Your Domain Name for certificates: "
read domain_name
echo -n "Your Cloudflare API Key: "
read cloudflare_key
echo -n "Email for Lets Encrypt: "
read email_address
echo -n "Installation directory [/opt/docker/traefik-stack]: "
read install_dir

# Set default if empty
install_dir=${install_dir:-/opt/docker/traefik-stack}

echo
echo "${CYAN}Creating directory structure...${END}"

# Create main directory structure
mkdir -p "$install_dir"

# change into the install directory
cd "$install_dir"

echo "${CYAN}Certificates will be stored in: ${YELLOW}$install_dir/traefik/config/certs/${END}"
echo "${CYAN}Dynamic configs monitored in: ${YELLOW}$install_dir/traefik/config/conf/${END}"
echo

echo "${CYAN}Downloading configuration files...${END}"

# Clone the repo to the install folder
TEMP_DIR=$(mktemp -d)
git clone https://github.com/MadJalapeno/homelab-traefik.git "$install_dir"
rm -r .git
rm install.sh

echo
echo "${CYAN}Configuring files with your information...${END}"

# Update .env file
mv .env.demo .env
echo "Updating .env file"
sed -i "s/cf-dns-replace-me/$cloudflare_key/g" .env
sed -i "s/your-token-here/$cloudflare_key/g" .env

# Update docker-compose.yml
echo "Updating docker-compose.yml"
sed -i "s/example.com/$domain_name/g" docker-compose.yml

# Update traefik config
sed -i "s/example.com/$domain_name/g" traefik/config/traefik.yml
sed -i "s/your-email/$email_address/g" traefik/config/traefik.yml


echo "${GREEN}Configuration complete${END}"
echo

# Create the proxy network if it doesn't exist
echo "${CYAN}Creating Docker network...${END}"
docker network create proxy 2>/dev/null && echo "${GREEN}Network 'proxy' created${END}" || echo "${YELLOW}Network 'proxy' already exists${END}"
echo


cd traefik
echo "${CYAN}Starting Traefik...${END}"
docker compose up traefik -d

echo "Waiting for Traefik to initialize..."
sleep 10
echo "${GREEN}Traefik started${END}"
echo

echo "${CYAN}Starting CrowdSec...${END}"
docker compose up crowdsec -d

echo "Waiting for CrowdSec to initialize (60 seconds)..."
for i in 60 50 40 30 20 10; do
    echo -n "$i "
    sleep 10
done
echo
echo "${GREEN}CrowdSec started${END}"
echo

echo "${CYAN}Configuring CrowdSec Bouncer...${END}"
echo "Generating API key..."

# Generate the bouncer API key
API_KEY=$(docker exec crowdsec cscli bouncers add traefik-bouncer -o raw 2>/dev/null)

if [ -z "$API_KEY" ]; then
    echo "${RED}Failed to generate API key. Trying alternative method...${END}"
    API_KEY=$(docker exec crowdsec cscli bouncers add traefik-bouncer-$(date +%s) -o raw)
fi

echo "${GREEN}API Key generated successfully${END}"
echo "API Key: ${CYAN}$API_KEY${END}"
echo

# Add the API key to the .env file
if grep -q "CROWDSEC_BOUNCER_API_KEY" .env; then
    sed -i "s/CROWDSEC_BOUNCER_API_KEY=.*/CROWDSEC_BOUNCER_API_KEY=$API_KEY/" .env
else
    echo "CROWDSEC_BOUNCER_API_KEY=$API_KEY" >> .env
fi

echo "${CYAN}Starting CrowdSec Bouncer...${END}"
docker compose up bouncer -d

echo "Waiting for bouncer to start..."
sleep 5
echo

echo "${GREEN}***************************************${END}"
echo "${GREEN}   Installation Complete!${END}"
echo "${GREEN}***************************************${END}"
echo
echo "${CYAN}Installation Summary:${END}"
echo "Installation directory: ${YELLOW}$install_dir${END}"
echo "Domain: ${YELLOW}$domain_name${END}"
echo "Traefik Dashboard: ${YELLOW}https://traefik.$domain_name${END}"
echo
echo "${CYAN}Services Status:${END}"
docker compose ps
echo
echo "${CYAN}Directory Structure:${END}"
echo "$install_dir/"
echo "├── docker-compose.yml    # Main stack configuration"
echo "├── .env                  # Environment variables"
echo "├── logs/                 # Traefik logs (monitored by CrowdSec)"
echo "├── traefik/"
echo "│   └── config/"
echo "│       ├── traefik.yml            # Main Traefik config"
echo "│       ├── certs/                 # SSL certificates (acme.json)"
echo "│       └── conf/                  # Dynamic configs (auto-monitored)"
echo "│           ├── README.md          # How to use dynamic configs"
echo "│           └── *.yml              # Add your service configs here"
echo "└── crowdsec/"
echo "    ├── config/           # CrowdSec configuration"
echo "    ├── data/             # CrowdSec data"
echo "    └── acquis.yaml       # Log acquisition config"
echo
echo "${CYAN}Certificate Information:${END}"
echo "  Location: ${YELLOW}$install_dir/traefik/config/certs/acme.json${END}"
echo "  Provider: Let's Encrypt via Cloudflare DNS-01 challenge"
echo "  Auto-renewal: Handled automatically by Traefik"
echo "  Wildcard cert: *.${domain_name} and ${domain_name}"
echo
echo "${CYAN}Dynamic Configuration:${END}"
echo "  Monitored directory: ${YELLOW}$install_dir/traefik/config/conf/${END}"
echo "  Add .yml files here to configure new services"
echo "  Changes are detected automatically (no restart needed)"
echo "  See README.md in that directory for examples"
echo
echo "${CYAN}Useful Commands (run from $install_dir):${END}"
echo "  ${YELLOW}docker compose ps${END}                    # View all services"
echo "  ${YELLOW}docker compose logs -f${END}               # View all logs"
echo "  ${YELLOW}docker compose logs -f traefik${END}       # View Traefik logs"
echo "  ${YELLOW}docker compose restart${END}               # Restart all services"
echo "  ${YELLOW}docker compose down${END}                  # Stop all services"
echo "  ${YELLOW}docker compose up -d${END}                 # Start all services"
echo
echo "${CYAN}CrowdSec Commands:${END}"
echo "  ${YELLOW}docker exec crowdsec cscli decisions list${END}      # View blocked IPs"
echo "  ${YELLOW}docker exec crowdsec cscli metrics${END}             # View metrics"
echo "  ${YELLOW}docker exec crowdsec cscli alerts list${END}         # View alerts"
echo "  ${YELLOW}docker exec crowdsec cscli bouncers list${END}       # View bouncers"
echo
echo "${GREEN}Done! Your Traefik security stack is running.${END}"
echo