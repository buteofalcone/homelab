Failed to create stream fd: Operation not permitted
Failed to create stream fd: Operation not permitted
Failed to create stream fd: Operation not permitted
# Домашній сервер Butenko — шпаргалка

## Почати

1. Увімкніть **Tailscale** на телефоні або комп’ютері. Потрібен стан **Connected**.
2. Відкрийте [Homepage](https://home.butenko.online) — там зібрані всі застосунки.
3. Увійдіть у потрібний застосунок зі своїм обліковим записом.

Адреси `hp-server.tail7cb430.ts.net` працюють тільки з підключеним Tailscale. Паролі зберігайте у [Vaultwarden](https://hp-server.tail7cb430.ts.net:8443/); майстер-пароль нікому не надсилайте.

## Щодня

| Що зробити | Куди зайти |
| --- | --- |
| Файли та сімейний чат | [Nextcloud](https://nextcloud.butenko.online) → **Talk** для повідомлень |
| Фото й автозавантаження з телефона | [Immich](https://immich.butenko.online) або мобільний застосунок Immich |
| Скановані документи й пошук у PDF | [Paperless](https://paperless.butenko.online) |
| Фільми та серіали | [Jellyfin](https://jellyfin.butenko.online) |
| Попросити додати фільм чи серіал | [Замовити](https://requests.butenko.online) — вхід через Jellyfin |
| Книги EPUB | [Books](https://books.butenko.online); на iPhone/iPad: **Поділитися → Books** |
| Аудіокниги й подкасти | [Audiobookshelf](http://hp-server.tail7cb430.ts.net:13378/) |
| Музика | [Navidrome](http://hp-server.tail7cb430.ts.net:4533/) |
| RSS-новини | [FreshRSS](http://hp-server.tail7cb430.ts.net:8084/) |
| Рецепти | [Mealie](http://hp-server.tail7cb430.ts.net:9925/) |
| Продукти й запаси | [Grocy](http://hp-server.tail7cb430.ts.net:9283/) |
| AI-чат | [Butenko AI](https://ai.butenko.online); доступність залежить від SilverBrick |

## Для власника

| Завдання | Застосунок |
| --- | --- |
| Додати або впорядкувати книги | [Calibre](https://calibre.butenko.online), [Calibre-Web Automated](http://hp-server.tail7cb430.ts.net:8083/) |
| Озвучити книгу або текст | [ebook2audiobook](http://hp-server.tail7cb430.ts.net:7860/), [Ukrainian TTS](http://hp-server.tail7cb430.ts.net:7861/) |
| Завантажити музику до бібліотеки | [Yubal](http://hp-server.tail7cb430.ts.net:8011/) → слухати в Navidrome |
| Керувати медіатекою | [Sonarr](https://sonarr.butenko.online), [Radarr](https://radarr.butenko.online), [Prowlarr](https://prowlarr.butenko.online), [qBittorrent](https://torrent.butenko.online) |
| Бази даних | [Adminer](http://hp-server.tail7cb430.ts.net:8085/), [Bytebase](http://hp-server.tail7cb430.ts.net:8086/) |
| Стан сервера | [Portainer](https://portainer.butenko.online), [Beszel](https://beszel.butenko.online), [Uptime Kuma](https://uptime.butenko.online) |

## Якщо не відкривається

- Перевірте Tailscale → **Connected** і ще раз відкрийте картку на Homepage.
- Для адрес `hp-server.tail7cb430.ts.net` не замінюйте **http** на **https**. Виняток — Vaultwarden, у нього HTTPS на порту `8443`.
- Якщо не працює Butenko AI, перевірте, чи увімкнений SilverBrick.
- Незамінні фото й документи зберігайте також в іншій незалежній резервній копії.
