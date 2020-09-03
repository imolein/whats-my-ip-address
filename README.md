# whats-my-ip

A tiny "Whats my IP address" - service written in [Lua](https://lua.org/), using the [lua-http](https://github.com/daurnimator/lua-http) library.

## Installation

Currently it is recommand to run this service behind nginx.

### Dependencies

* [Lua](https://www.lua.org/) (>= 5.1)
* [luarocks](https://luarocks.org) (>= 3.0.3)
* [lua-http](https://github.com/daurnimator/lua-http)
* [mimetypes](https://bitbucket.org/leafstorm/lua-mimetypes/)
* [luafilesystem](https://github.com/keplerproject/luafilesystem)

### Docker installation

There is an docker image, which is the easiest way to run this service. Just do

```
docker run -it -d --rm --init -p 127.0.0.1:9090:9090 imolein/wmia:latest
```

To configure the service you can run docker with the following environment variables:

`WMIA_HOST`, `WMIA_PORT`, `WMIA_HTML_ROOT`, `WMIA_DOMAIN`

for example:
```
docker run -it -d --rm --init -p 127.0.0.1:9090:9090 -e WMIA_HOST=0.0.0.0 -e WMIA_PORT=9090 -e WMIA_HTML_ROOT=./html -e WMIA_DOMAIN=example.com imolein/wmia:latest
```

Or you use docker-compose and the example `docker-compose.yaml` file from this repository.

### Manual installation

* [Install luarocks](https://github.com/luarocks/luarocks/wiki/Installation-instructions-for-Unix)
* Install **Lua** and **nginx**
```
apt install lua5.4 nginx
```
* Create a new user
```
adduser wmia
```

* Login as the user:
```
su -l wmia
```

* Clone the repository
```
git clone https://git.kokolor.es/imo/whats-my-ip-address.git
```

* Change into the new folder
```
cd whats-my-ip-address/
```

* Initialize **luarocks** for this project
```
luarocks init
luarocks init --reset    # see issue https://github.com/luarocks/luarocks/issues/924
```
The benefit is, that **luarocks** will now install new modules in this folder, which keeps the rest of the system clean. But if you want to install the modules for the whole user or the whole system you can do this as well.

* Now install the modules via **luarocks**
```
luarocks install http
luarocks install mimetypes
luarocks install luafilesystem
```

* Rename the sample config file and edit it with your favorite editor
```
cp config.cfg.lua{.sample,}
```

* Log back in as root and copy the **systemd** service file if you use systemd
```
cp /home/wmia/whats-my-ip-address/install/wmia.service /etc/systemd/system/
```

* Before activating the service, check if all paths are correct in the service file. If you didn't use `luarocks init` make sure you change the path to the **Lua** executable in **ExecStart**.
```
systemctl enable wmia.service
systemctl start wmia.service
```
If all paths are correctly, the service should start and be reachable locally

* I don't describe how to configure **nginx** here, but you can find an example configuration in **/install**, which you can use

## TODO

* maybe reverse dns
* maybe geoip = http://geoip.nekudo.com
