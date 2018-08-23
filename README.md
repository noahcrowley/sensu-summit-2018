# Sensu Influx Demo

First, clone the repo and create the data directories:

```
$ mkdir data data/chronograf/ data/influxdb/config/ data/influxdb/data/ data/sensu-backend/ data/sensu-agent/
```

## Start Your Containers...

### Docker Compose

There is a docker-compose file in this repo, so you can bring up all the components using `docker-compose up -d`.

### Docker Commands

If you'd like to create containers manually, first create a new bridge network, `sensu-net`:

```
docker create network sensu-net
```

Then bring up the individual containers and attach them to the `sensu-net` network. Remember to replace the `/path/to/local/directory/<service name>` with the directory path you plan on using.

```
docker run -d \
    --name sensu-backend \
    --network sensu-net \
    -p 2380:2380 \
    -p 3000:3000 \
    -p 8080:8080 \
    -p 8081:8081 \
    -v /path/to/local/directory/sensu-backend:/var/lib/sensu \
sensu/sensu:2.0.0-beta.4.1 sensu-backend start
```

```
docker run -d \
    --name sensu-agent \
    --network sensu-net \
    -v //path/to/local/directory/sensu-agent:/var/lib/sensu \
sensu/sensu:2.0.0-beta.4.1 sensu-agent start --backend-url ws://sensu-backend:8081 --subscriptions webserver,system --cache-dir /var/lib/sensu
```

```
docker run -d \
    --name influxdb \
    --network sensu-net \
    -p 8086:8086 \
    -p 8082:8082 \
    -p 8089:8089 \
    -v /path/to/local/directory/data:/var/lib/influxdb \
    -v /path/to/local/directory/sensu-influxdb/config:/etc/influxdb \
influxdb:1.6.1
```

```
docker run -d \
    --name chronograf \
    --network sensu-net \
    -p 8888:8888 \
    -v /path/to/local/directory/sensu-chronograf/data:/var/lib/chronograf \
chronograf:1.6.1
```
If you decide to create the containers using Docker commands, you'll need to update the commands in the following sections to use the container names specified above.

## Configure Sensuctl

[Install sensuctl](https://docs.sensu.io/sensu-core/2.0/getting-started/configuring-sensuctl/) and configure.

```
$ sensuctl configure
? Sensu Backend URL: http://127.0.0.1:8080
? Username: admin
? Password: P@ssw0rd!
? Organization: default
? Environment: default
? Preferred output format: none
```

## Agent and Check Setup

We're going to set up a simple check that outputs data in InfluxDB Line Protocol. First, we need to add the check script to the agent container, set the owner, and give it the appropriate permissions.

```
$ docker cp ./line_protocol.sh sensu-influx-demo_sensu-agent_1:/usr/local/bin/
$ docker exec sensu-influx-demo_sensu-agent_1 chown root:root /usr/local/bin/line_protocol.sh
$ docker exec sensu-influx-demo_sensu-agent_1 chmod +x /usr/local/bin/line_protocol.sh
```

Next, we'll create the check using sensuctl:

```
sensuctl check create check-line \
--command '/usr/local/bin/line_protocol.sh' \
--interval 20 \
--subscriptions webserver
```

# Handler Setup

We'll also need to add the handler to the backend. The current build of the handler is compiled with cgo, and thus relies on glibc, which is not present in the Alpine-based Sensu container. I've compiled a new version of the handler which is statically linked, and will work inside the container. You can [download it here](https://github.com/noahcrowley/sensu-influxdb-handler/releases/download/v1.5-influx/sensu-influxdb-handler). Or, using curl:

```
curl -LO https://github.com/noahcrowley/sensu-influxdb-handler/releases/download/v1.5-influx/sensu-influxdb-handler
```

Next, we'll copy the handler into the container, set the owner, and set the appropriate permissions:

```
docker cp ./sensu-influxdb-handler sensu-influx-demo_sensu_1:/usr/local/bin/
docker exec sensu-influx-demo_sensu_1 chown root:root /usr/local/bin/sensu-influxdb-handler
docker exec sensu-influx-demo_sensu_1 chmod +x /usr/local/bin/sensu-influxdb-handler
```

After that, we can create the handler using sensuctl:

```
sensuctl handler create influxdb \
--type pipe \
--command "/usr/local/bin/sensu-influxdb-handler --addr 'http://sensu-influx-demo_influxdb_1:8086' --db-name sensu --username user --password pass"
```

### Enable Handler for Check

Finally, configure the check with the appropriate metrics format and set it up to use the handler we just created:

```
sensuctl check set-output-metric-format check-line influxdb_line
sensuctl check set-output-metric-handlers check-line influxdb
```

## InfluxDB and Chronograf

Log into Chronograf at http://localhost:8888.

Connect to an InfluxDB instance. If you used Docker compose, the URL will be `http://sensu-influx-demo_influxdb_1:8086`. If you used the docker commands, the URL will be `http://influxdb:8086`.

Navigate to "InfluxDB admin" using the menu on the left-hand side.

Click the "Create Database" button to create a new database, and give it the name `sensu`.

### Run Some Queries

To access the InfluxDB CLI, execute a bash shell within the container. If you started up using Docker Compose:

```
$ docker exec -it sensu-influx-demo_influxdb_1 /bin/bash
```

Or using the Docker commands:

```
$ docker exec -it influxdb /bin/bash
```

and then start the CLI:

```
$ influx
```

Select the `sensu` database:

```
USE sensu
```

Retrieve all the data for the past hour:

```
SELECT * FROM randoms WHERE time > now()-1h
```

Calculate the mean of the data:

```
SELECT mean(*) FROM randoms WHERE time > now()-1h
```

Calculate the mean of the data in 1-minute windows:

```
SELECT mean(*) FROM randoms WHERE time > now()-1h GROUP BY time(1m)
```

Calculate the mean of the data in 1-minute windows, ignoring windows with no data:

```
SELECT mean(*) FROM randoms WHERE time > now()-1h GROUP BY time(1m) FILL(none)
```

Use a subquery to find the minute with the highest mean value:

```
SELECT max(mean_value) FROM (SELECT mean(*) FROM randoms WHERE time > now()-1h GROUP BY time(1m) FILL(none))
```