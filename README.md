# whats-my-ip

A tiny "Whats my IP address" - service written in [Lua](https://lua.org/), using the [lua-http](https://github.com/daurnimator/lua-http) library.

## Installation

Currently it is recommand to run this service behind nginx. In the future it should be possible to run it standalone too, but for this a few features are missing.
This installation assume you're using Debian or Ubuntu, but should work on other systems too, when you replace the package manager commands.

### Dependencies

* [Lua](https://www.lua.org/) (>= 5.1)
* [luarocks](https://luarocks.org) (>= 3.0.3)
* [lua-http](https://github.com/daurnimator/lua-http)
* [mimetypes](https://bitbucket.org/leafstorm/lua-mimetypes/)
* [luafilesystem](https://github.com/keplerproject/luafilesystem)
* [nginx](https://www.nginx.com/)

### Install dependencies

* [Install luarocks](https://github.com/luarocks/luarocks/wiki/Installation-instructions-for-Unix)
* Install **Lua** and **nginx**
```
apt install lua5.3 nginx
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

* Create Dockerfile
* Documentation (e.g. usage, installation)
* maybe reverse dns
* maybe geoip = http://geoip.nekudo.com