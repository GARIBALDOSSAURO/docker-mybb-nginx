#!/bin/sh
set -e

# Inicia o PHP-FPM em background
php-fpm -D

# Inicia o Nginx em primeiro plano (mantendo o processo principal ativo)
exec /usr/sbin/nginx -g 'daemon off;'
