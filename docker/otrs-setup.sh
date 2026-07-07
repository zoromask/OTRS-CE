#!/bin/bash
set -euo pipefail

OTRS_HOME="/opt/otrs"
OTRS_USER="otrs"
WEB_GROUP="apache"

cd "${OTRS_HOME}"

# Prepare configuration files from distribution templates.
cp Kernel/Config.pm.dist Kernel/Config.pm
mv Kernel/Config.pod.dist Kernel/Config.pod

for cron_file in var/cron/*.dist; do
    [[ -f "${cron_file}" ]] || continue
    mv "${cron_file}" "var/cron/$(basename "${cron_file}" .dist)"
done

cp .procmailrc.dist .procmailrc
cp .fetchmailrc.dist .fetchmailrc
cp .mailfilter.dist .mailfilter

mkdir -p var/tmp var/article var/log var/sessions var/spool var/run

# Create the OTRS system user expected by the RPM packaging workflow.
if ! id "${OTRS_USER}" >/dev/null 2>&1; then
    useradd "${OTRS_USER}" -d "${OTRS_HOME}" -s /bin/bash -g "${WEB_GROUP}" -c "OTRS System User"
else
    usermod -g "${WEB_GROUP}" -d "${OTRS_HOME}" "${OTRS_USER}"
fi

"${OTRS_HOME}/bin/otrs.SetPermissions.pl" --otrs-user="${OTRS_USER}" --web-group="${WEB_GROUP}"

# Apache integration for AlmaLinux/RHEL httpd.
ln -sf "${OTRS_HOME}/scripts/apache2-httpd.include.conf" /etc/httpd/conf.d/zzz_otrs.conf

if [[ -f /etc/httpd/conf.d/welcome.conf ]]; then
    sed -i 's|ErrorDocument 403 /.noindex.html|ErrorDocument 403 /otrs/index.pl|' /etc/httpd/conf.d/welcome.conf
fi

if [[ -f /var/www/html/index.html ]]; then
    cp /var/www/html/index.html /var/www/html/index.html.orig
    cp "${OTRS_HOME}/var/httpd/htdocs/index.html" /var/www/html/index.html
fi

sed -i 's/\bindex.html\b/& index.pl/' /etc/httpd/conf/httpd.conf
