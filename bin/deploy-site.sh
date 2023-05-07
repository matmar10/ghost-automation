#!/bin/bash

# Default values
SITE_NAME=""
DOMAIN=""
SSL_EMAIL=""
GODADDY_API_KEY=""
GODADDY_API_SECRET=""
MYSQL_ROOT_PASSWORD=""
GHOST_DB_NAME=""
INSTALL_DIR="/var/www"
NO_PROMPT=false
NO_OP=false

# Function to print the usage
print_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "  -s, --site-name            Site name (subdomain)"
  echo "  -d, --domain               Domain name"
  echo "  -i, --install-dir          Installation directory (default: /var/www)"
  echo "  -e, --ssl-email            SSL email"
  echo "  -k, --godaddy-api-key      GoDaddy API key"
  echo "  -r, --godaddy-api-secret   GoDaddy API secret"
  echo "  -p, --mysql-root-password  MySQL root password"
  echo "  -m, --db-name              MySQL DB name to install Ghost into"
  echo "  -n, --no-prompt            Run in non-interactive mode"
  echo "  -x, --no-op                No-op mode (dry-run)"
  echo ""
  echo "Example:"
  echo "  $0 -s bmt-makmur -d koperasipintar.org -i /opt/www/ -e email@example.com -k api_key -r api_secret -p mysql_root_password --no-prompt"
}

make_url_safe() {
  local input_string="$1"
  local url_safe_string=$(echo "$input_string" | sed 's/[^a-zA-Z0-9-]/-/g')
  echo "$url_safe_string"
}

make_db_safe() {
  local input_string="$1"
  local url_safe_string=$(echo "$input_string" | sed 's/[^a-zA-Z0-9_]/_/g')
  echo "$url_safe_string"
}

confirm_to_proceed() {
  # only prompt in interactive mode
  if [ "$NO_PROMPT" = false ]; then
    read -p "Do you want to proceed? (Yes/[No]): " response
    case "$response" in
      [yY][eE][sS]|[yY])
        echo "Proceeding with the action..."
        ;;
      *)
        echo "Cancelled."
        exit 1
        ;;
    esac
  fi
}

assert_required_arguments() {
  # Check if all required variables are provided
  if [ -z "$SITE_NAME" ] || [ -z "$DOMAIN" ] || [ -z "$SSL_EMAIL" ] || [ -z "$GODADDY_API_KEY" ] || [ -z "$GODADDY_API_SECRET" ] || [ -z "$MYSQL_ROOT_PASSWORD" ] || [ -z "$GHOST_DB_NAME" ]; then
    echo "Error: Missing required arguments."
    print_usage
    exit 2
  fi
}

get_cname_record() {
  curl -s -X GET "https://api.godaddy.com/v1/domains/${DOMAIN}/records/CNAME/${SITE_NAME}" \
    -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
    -H "Content-Type: application/json"
  local exit_status=$?
  if [ $exit_status -ne 0 ]; then
    echo "Error: Failed to get current DNS."
    exit 3
  fi
}

update_cname_record() {
  curl -s -X PUT "https://api.godaddy.com/v1/domains/${DOMAIN}/records/CNAME/${SITE_NAME}" \
    -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
    -H "Content-Type: application/json" \
    -d "[{\"data\": \"@\", \"ttl\": 3600}]"
  local exit_status=$?
  if [ $exit_status -ne 0 ]; then
    echo "Error: Failed to configure DNS."
    exit 4
  fi
}

configure_dns() {
  local current_cname_record=$(get_cname_record)
  if [ -z "${current_cname_record}" ] || [ "${current_cname_record}" == "[]" ]; then
    echo "Adding CNAME record for ${TARGET_DOMAIN} pointing to ${DOMAIN}"
    update_cname_record
    echo "CNAME record added successfully."
  else
    echo "Updating CNAME record for ${TARGET_DOMAIN} to point to ${DOMAIN}"
    update_cname_record
    echo "CNAME record updated successfully."
  fi
}

create_mysql_db() {
  local database_name="$1"
  local db_exists=$(mysql -u root -p"$MYSQL_ROOT_PASSWORD" -se "SELECT EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name = '$database_name');")

  if [ "$db_exists" -eq 1 ]; then
    echo "The MySQL database '$database_name' already exists."
  else
    echo "The MySQL database '$database_name' does not exist. Creating it..."
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE ${GHOST_DB_NAME};"
    local exit_status=$?
    if [ $exit_status -ne 0 ]; then
      echo "Error: Failed to create MySQL DB"
      exit 5
    fi
  fi
}

exit_if_noop() {
  if [ "$NO_OP" = true ]; then
    echo "(no-op mode) Done."
    exit 0
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -d|--domain)
      DOMAIN="$2"
      shift 2
      ;;
    -s|--site-name)
      RAW_SITE_NAME="$2"
      shift 2
      ;;
    -i|--install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    -e|--ssl-email)
      SSL_EMAIL="$2"
      shift 2
      ;;
    -k|--godaddy-api-key)
      GODADDY_API_KEY="$2"
      shift 2
      ;;
    -r|--godaddy-api-secret)
      GODADDY_API_SECRET="$2"
      shift 2
      ;;
    -p|--mysql-root-password)
      MYSQL_ROOT_PASSWORD="$2"
      shift 2
      ;;
    -m|--db-name)
      GHOST_DB_NAME="$2"
      shift 2
      ;;
    -n|--no-prompt)
      NO_PROMPT=true
      shift
      ;;
    -n|--no-op)
      NO_OP=true
      shift
      ;;
    *)
      print_usage
      exit 6
      ;;
  esac
done

SITE_NAME=$(make_url_safe "$RAW_SITE_NAME")
if [ "$SITE_NAME" != "$RAW_SITE_NAME" ]; then
  echo "Invalid site name: site name must be URL safe"
  exit 7
fi
GHOST_DB_NAME_SAFE=$(make_db_safe "$GHOST_DB_NAME")
if [ "$GHOST_DB_NAME_SAFE" != "$GHOST_DB_NAME" ]; then
  echo "Invalid db name: db name must be mysql safe/compatible"
  exit 8
fi
TARGET_DOMAIN="$SITE_NAME.$DOMAIN"
GHOST_DOMAIN="${GHOST_SITE_NAME}.${DOMAIN}"
GHOST_INSTALL_DIR="${INSTALL_DIR}/${SITE_NAME}"

assert_required_arguments

echo ""
echo "-- Deploy New Ghost Site ---- "
echo -e "Site Name:\t\t$SITE_NAME"
echo -e "Target Domain:\t\t$TARGET_DOMAIN"
echo -e "SSL Email:\t\t$SSL_EMAIL"
echo -e "MySQL DB:\t\t$GHOST_DB_NAME"
echo -e "Install Dir:\t\t$GHOST_INSTALL_DIR"
echo ""

confirm_to_proceed

exit_if_noop

echo ""
echo " > Configuring DNS"
get_cname_record
configure_dns
echo ""

echo ""
echo " > Setting up MySQL"
create_mysql_db $GHOST_DB_NAME
echo ""

echo ""
echo " > Installing Ghost"
mkdir -p ${GHOST_INSTALL_DIR}
chown -R $USER:$USER ${GHOST_INSTALL_DIR}
chmod 755 ${GHOST_INSTALL_DIR}
cd ${GHOST_INSTALL_DIR}
ghost install \
	--db mysql \
	--dbhost localhost \
	--dbuser root \
	--dbpass ${MYSQL_ROOT_PASSWORD} \
	--dbname ${GHOST_DB_NAME} \
	--url "http://${TARGET_DOMAIN}" \
	--sslemail "${SSL_EMAIL}" \
	--no-prompt
echo ""

