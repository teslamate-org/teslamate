## Development Setup

### Docker Compose Development Environment

The `docker-compose.dev.yaml` file has been configured to automatically pick up changes to Grafana dashboards and configuration files.

#### Features:

- **Automatic Dashboard Updates**: Grafana will automatically reload dashboard changes every 5 seconds
- **Live Configuration**: All Grafana configuration files are mounted from the host system
- **Development-Friendly**: Includes health checks and proper volume mounting for hot reloading

#### Usage:

1. Start the development environment:
   ```bash
   docker-compose -f docker-compose.dev.yaml up
   ```

2. Edit any dashboard files in `grafana/dashboards/`

3. Changes will be automatically picked up by Grafana within 5 seconds

4. Access Grafana at http://localhost:3000 (admin/admin)

#### Configuration Files:

- `grafana/grafana.ini` - Main Grafana configuration
- `grafana/dashboards.yml` - Dashboard provisioning configuration
- `grafana/datasource.yml` - Data source configuration
- `grafana/dashboards/` - All dashboard JSON files

#### Auto-Reload Settings:

- Dashboard update interval: 5 seconds (configurable in `grafana/dashboards.yml`)
- Configuration files are mounted read-only for security
- Health checks ensure Grafana is running properly