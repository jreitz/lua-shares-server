# lua-shares-server - A Counts Server

lua-shares runs in nginx to provide a single API request return all your social-share counts. Each social network is queried server-side and in parallel. Typically this saves more than a second of page load time and can prevent your page from hanging if one of the social APIs is down or slow. lua-shares can also cache the social counts in memcached for even faster response times on your popular pages. It can easily handle very high request volume, with consistent, low latency. On modest hardware, time to first byte is sub-5ms for cached URLs and there is negligible latency on top of the slowest returning social API for uncached requests.

lua-shares was inspired by the tfrce/social-buttons-server which runs on Node. It aims to have an identical API so that any social buttons should work with either implementation.

## Features
* Fast and simple
* Supports Pinterest, LinkedIn, Twitter and Facebook
* Configurable whitelist to only query for your own URLs
* Memcached caching with configurable time-to-live
* Expires header support for easy CDN caching


## Dependencies
* lua - [LuaJIT](http://luajit.org/) recommended
* nginx with the [lua-nginx-module](https://github.com/chaoslawful/lua-nginx-module) or the [ngx_openresty bundle](http://openresty.org/)
* Lua CJSON - JSON library, http://www.kyne.com.au/~mark/software/lua-cjson.php (included in openresty)
* Resty HTTP Simple - HTTP client, https://github.com/bakins/lua-resty-http-simple
* Resty Memcached - Optional memcached client, https://github.com/agentzh/lua-resty-memcached (included in openresty)


## Installation

Clone the reponsitory to your preferred location (/usr/local/share/lua-shares-server is a sensible path on Debian/Ubuntu).

```
$ git clone git@github.com:jreitz/lua-shares-server.git /usr/local/share/lua-shares-server
```

In your nginx config, reference lua-shares.lua at the location of your choosing e.g. / for a standalone installation or something like /lua-shares within a more complex configuration.

```nginx

lua_package_path '/usr/local/share/lua-shares/server/?.lua;;';
init_by_lua '
    shares = require "lua_shares"
';

server {
    location = /lua-shares {
        content_by_lua 'shares.get_counts()';
    }
}
```

Reload nginx and test the API:

```
curl http://hubpages.com/lua-shares/?url=http://hubpages.com
```

Write some JS and make some social buttons that use this server and tell me about them so that I can reference them here.

## Usage

### API parameters

Lua-shares responds to two optional query parameters:

#### url=

The URL for which you want to receive social-shares count information. If this parameter is missing, the referrer, which normally points to the calling page, is used. If no scheme is provided, http: will be assumed.

#### networks

A comma-seperated list of social networks to be queried. Supported values are: facebook,pinterest,twitter,linkedin. If not provided, the default networks queried are: facebook,pinterest,twitter.

### Advanced configuration

The lua source contains a number of options for memcached server, timeouts and other behavior. Look there for more details.


## TODO
* Self-contained or embedded HTTP client
* Self-contained reference social-buttons implementation
* Prefetching popular URLs
* API timing and statsd support; for monitoring upstream social APIs
* Google-plus support (currently waiting on TLS support from lua-nginx)


## License
The MIT License (MIT)

Copyright (c) 2014 Jay Reitz

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

