# Ensure selecting a tag that is available for arm64 and amd64
# https://hub.docker.com/r/grafana/grafana/tags
FROM grafana/grafana:13.0.1-security-01

ENV GF_ANALYTICS_REPORTING_ENABLED=false \
    GF_ANALYTICS_CHECK_FOR_UPDATES=false \
    GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=false \
    GF_ANALYTICS_FEEDBACK_LINKS_ENABLED=false \
    GF_AUTH_ANONYMOUS_ENABLED=false \
    GF_AUTH_BASIC_ENABLED=false \
    GF_SECURITY_ADMIN_PASSWORD=admin \
    GF_SECURITY_ADMIN_USER=admin \
    GF_SECURITY_ALLOW_EMBEDDING=true \
    GF_SECURITY_DISABLE_GRAVATAR=true \
    GF_DATABASE_HIGH_AVAILABILITY=false \
    GF_USERS_ALLOW_SIGN_UP=false \
    GF_USERS_DEFAULT_LANGUAGE=detect \
    GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/dashboards_internal/home.json \
    GF_DATE_FORMATS_USE_BROWSER_LOCALE=true \
    GF_PLUGINS_PREINSTALL_DISABLED=true \
    GF_UNIFIED_ALERTING_ENABLED=false \
    GF_METRICS_ENABLED=false \
    GF_RECORDING_RULES_ENABLED=false \
    GF_CLOUD_MIGRATION_ENABLED=false \
    GF_FEATURE_TOGGLES_provisioning=false \
    GF_FEATURE_TOGGLES_splashScreen=false \
    GF_FEATURE_TOGGLES_newPanelPadding=false \
    GF_FEATURE_TOGGLES_dashboardNewLayouts=false \
    DATABASE_PORT=5432 \
    DATABASE_SSL_MODE=disable

USER grafana

COPY logo.svg /usr/share/grafana/public/build/img/grafana_icon.svg

RUN LOGO_PATH=$(find /usr/share/grafana/public/build/static/img/ -type f -name 'grafana_icon.*.svg') && \
    cp /usr/share/grafana/public/build/img/grafana_icon.svg "$LOGO_PATH" || true

COPY favicon.png /usr/share/grafana/public/build/img/fav32.png
COPY apple-touch-icon.png /usr/share/grafana/public/build/img/apple-touch-icon.png

COPY datasource.yml /etc/grafana/provisioning/datasources/
COPY dashboards.yml /etc/grafana/provisioning/dashboards/
COPY dashboards/internal/*.json /dashboards_internal/
COPY dashboards/reports/*.json /dashboards_reports/
COPY dashboards/*.json /dashboards/

EXPOSE 3000
