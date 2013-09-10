# lua-shares-server - A Social Counts Server

lua-shares runs in nginx to provide a single API request return all your social-share counts. Each social network is queried server-side and in parallel. lua-shares can also cache the social counts in memcached for even faster response times on your popular pages. It can easily handle very high request volume, with consistent, low latency.

lua-shares was inspired by the tfrce/social-buttons-server which runs on Node. It aims to have a (mostly) indentical API so that any social buttons should work with either implementation.

## Features
* Fast and simple
* Supports Pinterest, Twitter and Facebook
* Memcached caching with configurable time-to-live


## Requirements
* lua - [LuaJIT](http://luajit.org/) recommended
* nginx with the [lua-nginx-module](https://github.com/chaoslawful/lua-nginx-module) or the [ngx_openresty bundle](http://openresty.org/)
* Lua CJSON - JSON library, http://www.kyne.com.au/~mark/software/lua-cjson.php (included in openresty)
* Resty Memcached - Memcached client, https://github.com/agentzh/lua-resty-memcached (included in openresty)
* Resty HTTP Simple - HTTP client, https://github.com/bakins/lua-resty-http-simple


## Installation

1. Clone the reponsitory to your preferred location (/usr/local/share/lua-shares-server is a sensible path on Debian/Ubuntu).
2. Reference lua-shares.lua from the location of your choosing e.g. / for a standalone installation or /lua-shares within a more complex configuration.

```nginx

init_by_lua 'cjson = require "cjson"';

server {

    location = /lua-shares {
        access_log off;
        content_by_lua_file "/usr/local/share/lua-shares-server/lua-shares.lua";
    }
}
```

3. Reload nginx and test the API:

    curl http://hubpages.com/lua-shares/?url=http://hubpages.com


## TODO
* Handle more exotic URLs; respond only for specific whitelisted URLs
* Google-plus support (currently waiting on TLS support from lua-nginx)
* LinkedIn support
* Self-contained or embedded HTTP client
* Self-contained social-buttons implementation
* API timing and statsd support; for monitoring upstream social APIs


## License
The MIT License (MIT)

Copyright (c) 2013 Jay Reitz

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

