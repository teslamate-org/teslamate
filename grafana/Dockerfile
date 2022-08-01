FROM grafana/grafana:8.5.9

ENV GF_ANALYTICS_REPORTING_ENABLED=FALSE \
    GF_AUTH_ANONYMOUS_ENABLED=false \
    GF_AUTH_BASIC_ENABLED=false \
    GF_PATHS_PLUGINS="/var/lib/grafana-plugins" \
    GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=natel-discrete-panel,pr0ps-trackmap-panel,panodata-map-panel,natel-plotly-panel \
    GF_SECURITY_ADMIN_PASSWORD=admin \
    GF_SECURITY_ADMIN_USER=admin \
    GF_SECURITY_ALLOW_EMBEDDING=true \
    GF_SECURITY_DISABLE_GRAVATAR=true \
    GF_USERS_ALLOW_SIGN_UP=false \
    GF_ANALYTICS_REPORTING_ENABLED=FALSE \
    DATABASE_PORT=5432

USER root

RUN mkdir -p "$GF_PATHS_PLUGINS" && \
    chown -R grafana "$GF_PATHS_PLUGINS"

USER grafana

RUN grafana-cli --pluginsDir "${GF_PATHS_PLUGINS}" plugins install pr0ps-trackmap-panel 2.1.2 && \
    grafana-cli --pluginsDir "${GF_PATHS_PLUGINS}" plugins install natel-plotly-panel 0.0.7 && \
    grafana-cli --pluginsDir "${GF_PATHS_PLUGINS}" --pluginUrl https://github.com/panodata/panodata-map-panel/releases/download/0.16.0/panodata-map-panel-0.16.0.zip plugins install grafana-worldmap-panel-ng

COPY logo.svg /usr/share/grafana/public/img/grafana_icon.svg
COPY favicon.png /usr/share/grafana/public/img/fav32.png
COPY apple-touch-icon.png /usr/share/grafana/public/img/apple-touch-icon.png

COPY datasource.yml /etc/grafana/provisioning/datasources/
COPY dashboards.yml /etc/grafana/provisioning/dashboards/
COPY dashboards/internal/*.json /dashboards_internal/
COPY dashboards/reports/*.json /dashboards_reports/
COPY dashboards/*.json /dashboards/

EXPOSE 3000
