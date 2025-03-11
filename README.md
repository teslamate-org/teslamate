# TeslaMate DIY版本
更适合中国宝宝的配方，通过开放自定义地址反查接口和grafana地图配置文件，解决国内用户需要到处挂梯子才能显示地图、显示行程地址的痛点。

 - 自定义地址反向查询URL（Docker env: NOMINATIM_API_HOST）  
   **服务可以通过nominatim容器自建，仅使用反向查询接口消耗的资源很少**
 - 自定义grafana地图组件使用的默认地图源  
   **服务当然也可以自建，但是比较耗费系统资源，我更推荐免费的API[Thunderforest，一个月15万次免费调用，非常充足](https://www.thunderforest.com/)**
 - 最新版本增加了行程中的速度颜色区分，清晰地展示了一段行程中在哪个位置堵车、在哪个位置放飞自我~

## 供参考的配置文件
1. docker-compose.yml
```yml
services:
  nominatim:
    image: mediagis/nominatim:4.4
    restart: always
    environment:
      # see https://github.com/mediagis/nominatim-docker/tree/master/4.4#configuration for more options
      PBF_URL: https://download.geofabrik.de/asia/china-latest.osm.pbf
      REPLICATION_URL: https://download.geofabrik.de/asia/china-updates/
      REVERSE_ONLY: "true" #只做地址反查，性价比极高
      NOMINATIM_PASSWORD: password #insert your secure database password!
      TZ: Asia/Shanghai
    volumes:
        - nominatim-data:/var/lib/postgresql/14/main

  teslamate:
    image: ghcr.io/senmizu/teslamate_cn:1.32.0.14
    restart: always
    environment:
      - ENCRYPTION_KEY=secretkey #replace with a secure key to encrypt your Tesla API tokens
      - DATABASE_USER=teslamate
      - DATABASE_PASS=password #insert your secure database password!
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=database
      - MQTT_HOST=mosquitto
      - NOMINATIM_API_HOST=http://nominatim:8080  #就这样就行了
      - TZ=Asia/Shanghai
    ports:
      - 4000:4000
    volumes:
      - ./import:/opt/app/import
    cap_drop:
      - all
    depends_on:
      - nominatim

  database:
    image: postgres:15
    restart: always
    environment:
      - POSTGRES_USER=teslamate
      - POSTGRES_PASSWORD=password #insert your secure database password!
      - POSTGRES_DB=teslamate
      - TZ=Asia/Shanghai
    volumes:
      - teslamate-db:/var/lib/postgresql/data

  grafana:
    image: ghcr.io/senmizu/teslamate_cn/grafana:1.32.0.14
    restart: always
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=password #insert your secure database password!
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=database
      - TZ=Asia/Shanghai
    ports:
      - 3000:3000
    volumes:
      - teslamate-grafana-data:/var/lib/grafana
      - /your_path_to_container_config_files/grafana-config/grafana.ini:/etc/grafana/grafana.ini:ro #具体配置内容参照后面内容
      
  mosquitto:
    image: eclipse-mosquitto:2
    restart: always
    command: mosquitto -c /mosquitto-no-auth.conf
    ports:
      - 1883:1883 #不需要可以参照官方文档不使用，我用homeassistant集成需要这个端口
    volumes:
      - mosquitto-conf:/mosquitto/config
      - mosquitto-data:/mosquitto/data
    environment:
      - TZ=Asia/Shanghai

volumes:
  teslamate-db:
  teslamate-grafana-data:
  mosquitto-conf:
  mosquitto-data:
  nominatim-data:
```   

2. grafana.ini
```ini
[geomap]
# Set the JSON configuration for the default basemap
default_baselayer_config = `{
  "type": "xyz",
  "config": {
    "attribution": "Thunderforest",
    "url": "https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=your_api_key"
  }
}`
```


## Credits

- Initial Author: Adrian Kumpf
- List of Contributors:
- [![TeslaMate Contributors](https://contrib.rocks/image?repo=teslamate-org/teslamate)](https://github.com/teslamate-org/teslamate/graphs/contributors)
- Distributed under MIT License
