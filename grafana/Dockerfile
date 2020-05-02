FROM grafana/grafana:6.7.3

ENV  GF_ANALYTICS_REPORTING_ENABLED=FALSE \
     GF_AUTH_BASIC_ENABLED=false \
     GF_AUTH_ANONYMOUS_ENABLED=true \
     GF_SECURITY_ADMIN_PASSWORD=admin \
     GF_SECURITY_ADMIN_USER=admin \
     GF_SECURITY_ALLOW_EMBEDDING=true \
     GF_SECURITY_DISABLE_GRAVATAR=true \
     GF_USERS_ALLOW_SIGN_UP=false \
     GF_INSTALL_PLUGINS=pr0ps-trackmap-panel,natel-discrete-panel,grafana-piechart-panel,https://github.com/panodata/grafana-map-panel/releases/download/0.9.0/grafana-map-panel-0.9.0.zip;grafana-worldmap-panel-ng \
     DATABASE_PORT=5432

COPY datasource.yml /etc/grafana/provisioning/datasources/
COPY dashboards.yml /etc/grafana/provisioning/dashboards/
COPY dashboards/internal/*.json /dashboards_internal/
COPY dashboards/*.json /dashboards/

EXPOSE 3000
