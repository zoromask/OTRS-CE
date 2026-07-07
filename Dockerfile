# OTRS Community Edition 6.0.41 on AlmaLinux 9.8
FROM almalinux:9.8

LABEL maintainer="VPBank"
LABEL org.opencontainers.image.title="OTRS Community Edition"
LABEL org.opencontainers.image.version="6.0.41"
LABEL org.opencontainers.image.description="OTRS CE 6.0.41 with Apache mod_perl on AlmaLinux 9.8"

ENV OTRS_VERSION=6.0.41 \
    OTRS_HOME=/opt/otrs \
    OTRS_USER=otrs \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8

# Runtime and build dependencies for OTRS on AlmaLinux 9.
RUN dnf install -y epel-release \
    && crb enable \
    && dnf install -y \
        bzip2 \
        cronie \
        gcc \
        httpd \
        httpd-devel \
        make \
        mod_perl \
        perl \
        perl-core \
        procmail \
        shadow-utils \
        tar \
        which \
        "perl(Archive::Zip)" \
        "perl(Crypt::SSLeay)" \
        "perl(Net::LDAP)" \
        "perl(URI)" \
        "perl(Date::Format)" \
        "perl(LWP::UserAgent)" \
        "perl(Net::DNS)" \
        "perl(IO::Socket::SSL)" \
        "perl(XML::Parser)" \
        "perl(Crypt::Eksblowfish::Bcrypt)" \
        "perl(Encode::HanExtra)" \
        "perl(GD)" \
        "perl(GD::Text)" \
        "perl(GD::Graph)" \
        "perl(JSON::XS)" \
        "perl(Mail::IMAPClient)" \
        "perl(DateTime)" \
        "perl(Text::CSV_XS)" \
        "perl(YAML::XS)" \
        "perl(DBD::mysql)" \
        "perl(DBD::Pg)" \
        "perl(DBI)" \
        "perl(Authen::SASL)" \
        "perl(Authen::NTLM)" \
        "perl(Template)" \
        "perl(XML::LibXML)" \
        "perl(XML::LibXSLT)" \
        perl-Moo \
        "perl(namespace::clean)" \
        "perl(Crypt::Random::Source)" \
        "perl(Exporter::Tiny)" \
        "perl(Math::Random::ISAAC)" \
        "perl(Math::Random::Secure)" \
        "perl(Module::Find)" \
        "perl(Types::TypeTiny)" \
        perl-Template-Toolkit \
    && cpan -T PDF::API2 \
    && dnf clean all \
    && rm -rf /var/cache/dnf

COPY . ${OTRS_HOME}/

COPY docker/otrs-setup.sh /tmp/otrs-setup.sh
RUN chmod 755 /tmp/otrs-setup.sh \
    && /tmp/otrs-setup.sh \
    && rm -f /tmp/otrs-setup.sh \
    && perl ${OTRS_HOME}/bin/otrs.CheckModules.pl

COPY docker/bootstrap-k8s.pl ${OTRS_HOME}/bin/bootstrap-k8s.pl
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 ${OTRS_HOME}/bin/bootstrap-k8s.pl /usr/local/bin/entrypoint.sh \
    && ln -sf /dev/stdout /var/log/httpd/access_log \
    && ln -sf /dev/stderr /var/log/httpd/error_log

WORKDIR ${OTRS_HOME}

EXPOSE 80

VOLUME ["${OTRS_HOME}/Kernel", "${OTRS_HOME}/var"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD /usr/bin/curl -fsS http://127.0.0.1/otrs/installer.pl >/dev/null || /usr/bin/curl -fsS http://127.0.0.1/otrs/index.pl >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
