# ghost-automation

Various tool soft automating ghost hosting

## Pre-Requisites

- [Godaddy API Key & Secret](https://developer.godaddy.com/getstarted)
- Linux server (tested on Ubuntu 22.04)
- MySQL
- Nginx
- Node


## Deploying Ghost to New Subdomain

```Bash
./bin/deploy-site.sh \
  --domain "yourdomain.com" \
  --site-name "newsite" \
  --ssl-email "yourname@email.com" \
  --godaddy-api-key "yourkey" \
  --godaddy-api-secret "yoursecret" \
  --mysql-root-password "yourmysqlrootpassword"
```

This will deploy a new ghost site under `/var/www/newsite/`  hosted on the domain `newsite.yourdomain.com`.

