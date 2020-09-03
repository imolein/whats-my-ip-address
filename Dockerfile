FROM imolein/luarocks:5.4 as build

LABEL maintainer = "Sebastian Huebner <sh@kokolor.es>"

RUN luarocks install http \
    && luarocks install mimetypes \
    && luarocks install luafilesystem

FROM imolein/lua:5.4

ENV wdir /opt/wmia
WORKDIR ${wdir}

COPY --from=build /usr/local/share/lua/5.4 /usr/local/share/lua/5.4
COPY --from=build /usr/local/lib/lua/5.4 /usr/local/lib/lua/5.4
COPY html html/
COPY wmia.lua ./

RUN adduser -h ${wdir} -D wmia \
    && chown -R wmia:wmia ${wdir}

USER wmia

CMD ["lua", "wmia.lua"]
