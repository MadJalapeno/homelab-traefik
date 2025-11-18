echo "V 0.0.1"


# colorful output
RED="\e[31m"
CYAN="\e[32m"
END="\e[0m"

echo "*******"
echo "Checking ports available"
echo "*******"
echo 

if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null ; then
    echo "${RED}Port 80 busy${END}"
    echo lsof -Pi :80 
    exit
else
    echo "Port 80 free"
fi

if lsof -Pi :4431 -sTCP:LISTEN -t >/dev/null ; then
    echo "Port 443 busy"
    exit
else
    echo "Port 443 free"
fi

if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null ; then
    echo "Port 8080 busy"
    exit
else
    echo "Port 8080 free"
fi

echo
echo "Looks good"
echo

# Get info for installation
echo -n "Your Domain Name: "
read domain_name
echo -n "Your Cloudflare API Key: "
read cloudflare_key
echo -n "Email for Lets Encrypt: "
read email_address
echo

#download install files
git clone https://github.com/MadJalapeno/homelab-traefik.git

# move files and folders so they're easier to find
mv homelab-traefik/traefik .
mv homelab-traefik/crowdsec .

cd traefik

# rename .env file
mv .env.demo .env

# update cloudflare API key in .env file
sed -i -e "s/cf-dns-replace-me/$cloudflare_key/g" .env
sed -i -e "s/example.com/$domain_name/g" docker-compose.yml
sed -i -e "s/your-email/$email_address/g" ./config/traefik.yml

echo
echo "${CYAN}Installing ... ${END}"
echo
docker compose up traefik -d

# wait for things to start
echo "Waiting ..."
sleep 10
echo "Still Waiting ..."
sleep 10
echo "Alsmost Done ..."
sleep 10

API_KEY = `docker exec crowdsec cscli bouncers add traefik-bouncer`

echo API_KEY

#docker compose down