# WordPress-spezifisch

- Gravatar in Kommentaren: In `functions.php` deaktivieren oder `show_avatars` Option abschalten
- WordPress-Emojis (laden von twemoji.maxcdn.com): In `functions.php` mit `remove_action` deaktivieren
- Jetpack: Prüfen welche Module aktiv sind, viele übertragen Daten an Automattic (US)
- Contact Form 7: Daten-Speicherung konfigurieren, AVV mit Flamingo wenn Einträge gespeichert werden
- XML-RPC: Deaktivieren wenn nicht benötigt (`add_filter('xmlrpc_enabled', '__return_false')`)
- readme.html + license.txt: Löschen oder per .htaccess blockieren (verraten WordPress-Version)
- wp-json/wp/v2/users: User-Enumeration deaktivieren (REST API einschränken)
