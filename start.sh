#!/bin/sh
set -e

echo ">>> Starting PanSou backend service in the background..."
/app/pansou &

echo ">>> Starting Nginx in the foreground..."
nginx -g "daemon off;"
