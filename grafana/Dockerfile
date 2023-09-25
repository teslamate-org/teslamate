FROM grafana/grafana:latest

ENV GF_ANALYTICS_REPORTING_ENABLED=false \
    GF_PANELS_ENABLE_ALPHA=true \
    GF_INSTALL_PLUGINS=https://github.com/panodata/panodata-map-panel/releases/download/0.16.0/panodata-map-panel-0.16.0.zip;grafana-worldmap-panel-ng,pr0ps-trackmap-panel,natel-plotly-panel \
    GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=panodata-map-panel \
    DATABASE_PORT=5432 \
    DATABASE_SSL_MODE=disable

COPY logo.svg /usr/share/grafana/public/img/grafana_icon.svg
COPY favicon.png /usr/share/grafana/public/img/fav32.png
COPY apple-touch-icon.png /usr/share/grafana/public/img/apple-touch-icon.png

COPY datasource.yml /etc/grafana/provisioning/datasources/
COPY dashboards.yml /etc/grafana/provisioning/dashboards/
COPY dashboards/internal/*.json /dashboards_internal/
COPY dashboards/reports/*.json /dashboards_reports/
COPY dashboards/*.json /dashboards/

