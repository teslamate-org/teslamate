# Installation on DigitalOcean

## Introduction

In addition to self-hosting your TeslaMate installation on your local LAN, it is also possible to host your installation in a Cloud provider environment, which ensures that your TeslaMate instance is publicly available and accessible.

DigitalOcean provides a Docker image, on which Docker containers can be deployed. This allows the recommended installation method to be performed for TeslaMate.

A detailed walkthrough of the DigitalOcean installation process has been created by [spacecosmos](https://satheesh.net/2019/09/28/teslamate-digitalocean-docker-step-by-step-installation-guide/) and is highly recommended.

The following sections provide a brief overview of the steps involved.

## Docker Installation

### Create a DigitalOcean droplet

  * Create a new [DigitalOcean Droplet](https://m.do.co/c/98c628ea4a8e) and select the **Docker** image from the Marketplace tab.
  * Select your preferred plan for this Droplet.

### Create Docker container 
  * Edit the [docker-compose.yml](https://github.com/adriankumpf/teslamate/README.md) example template and specify the IP address of the DigitalOcean droplet.
  * Place the docker-compose.yml file on the DigitalOcean Droplet (via SCP, for example).
  
### Start Docker Containerx

Run the following command to start the Docker containers:

```
docker-compose up
```

### Test Connectivity

Using your browser, connect to the following URLs to test that the TeslaMate components are running:

  * http://*[ip of DigitalOcean droplet]*:4000/
     * This is the TeslaMate GUI. You should sign in with your Tesla username and password to start tracking your vehicles.
  * http://*[ip of DigitalOcean droplet]*:3000/
