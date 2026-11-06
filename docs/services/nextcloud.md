# Nextcloud

Start:

```bash
make nextcloud
```

Direct URL: `http://SERVER_IP:8080`  
HTTPS URL: `https://nextcloud.BASE_DOMAIN`

Application state and PostgreSQL data reside on SSD. User files reside at `/srv/storage/files/nextcloud` on HDD.

The image is pinned to Nextcloud major version 33. Upgrade one major version at a time and take a tested backup first.
