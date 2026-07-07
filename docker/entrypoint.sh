#!/bin/bash
set -euo pipefail

# Start OTRS background services when the application is already configured.
if [[ -f /opt/otrs/Kernel/Config.pm ]] && grep -q "Database" /opt/otrs/Kernel/Config.pm; then
    /opt/otrs/bin/otrs.Daemon.pl start || true
    /opt/otrs/bin/Cron.sh start || true
fi

exec /usr/sbin/httpd -DFOREGROUND
