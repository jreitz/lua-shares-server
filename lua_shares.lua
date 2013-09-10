-- lua-shares server
-- by Jay Reitz <jreitz@gmail.com>
-- (inspired by tfrce/social-buttons-server)
--

-- http fetch configuration
http_fetch_timeout = 3000 -- msecs

-- memcached cache configuration:
memcached = require "resty.memcached" -- comment out this line to disable memcached caching
memcached_ttl = 300 -- secs (0 is never expire)
memcached_key_prefix = "luashares:" -- url is appended
memcached_host = "127.0.0.1" -- only a single host is currently supported
memcached_pool_size = 40


local function error_say(...)
  ngx.log(ngx.WARN, ...)
  -- return -- uncomment to disable showing errors in the response
  ngx.print("/* ")
  ngx.print(...)
  ngx.say(" */")
end

-- returns memcached connection to keepalive pool for future reuse
-- (also closes connection)
local function set_memcached_pool(memc)
  local ok, err = memc:set_keepalive(0, memcached_pool_size) -- 0: no timeout of connections in pool
  if not ok then
    ngx.log(ngx.ERR, "Cannot set memcached keepalive: ", err)
  end
end

local function query_memcached()
  -- memc is global because it is re-used to persist data
  memc = memcached:new()
  memc:connect(memcached_host, 11211)
  local res, err = memc:get(memcached_key_prefix .. url)
  if res then
    -- if the get succeeded, we're done with this memcached connection
    set_memcached_pool(memc)
  end
  return res
end

local function persist_memcached(json)
  local ok, err = memc:set(memcached_key_prefix .. url, json, memcached_ttl)
  if not ok then
    ngx.log(ngx.ERR, "Cannot persist lua-shares to memcached: ", err)
    return
  end
  set_memcached_pool(memc)
end

local function query_twitter()
  local http = require "resty.http.simple"
  local res, err = http.request("urls.api.twitter.com", 80, {
    path    = "/1/urls/count.json",
    query   = { ["url"] = url },
    timeout = http_fetch_timeout,
  })

  if res then
    if res.status == ngx.HTTP_OK then
      res.data = cjson.decode(res.body)
      if res.data and res.data.count then
        return res.data.count
      end
    end
    error_say("http twitter bad response: ", res.body)
  else
    error_say("http twitter request error: ", err)
  end
  return -1
end

local function query_facebook()
  local http = require "resty.http.simple"
  local res, err = http.request("graph.facebook.com", 80, {
    path    = "/",
    query   = { ["id"] = url },
    headers = { ["Accept"] = "application/json" },
    timeout = http_fetch_timeout,
  })

  if res then
    if res.status == ngx.HTTP_OK then
      res.data = cjson.decode(res.body)
      if res.data and res.data.shares then
        return res.data.shares
      else
        -- facebook does not include "shares" key for un-shared url
        return 0
      end
      error_say("http facebook bad response: ", res.body)
    end
  else
    error_say("http facebook error: ",err)
  end
  return -1
end

local function query_pinterest()
  local http = require "resty.http.simple"
  local res, err = http.request("api.pinterest.com", 80, {
    path    = "/v1/urls/count.json",
    query   = { ["url"] = url, ["callback"] = "" },
    headers = { ["Accept"] = "application/json" },
    timeout = http_fetch_timeout,
  })

  if res then
    if res.status == ngx.HTTP_OK then
      -- first, remove surrounding ( and )
      local scrubbed_body = string.match(res.body, "^%(([^)]+)")
      res.data = cjson.decode(scrubbed_body)
      if res.data and res.data.count then
        return res.data.count
      end
      error_say("http pinterest bad response: ", res.body)
    end
  else
    error_say("http pinterest error: ", err)
  end
  return -1
end

--
-- main

-- parse incoming url= param
-- (test url: http://hubpages.com/hub/Michigan-Accent)
url = ngx.req.get_uri_args()["url"]
if not url then
  error_say("Missing required \"url\" parameter")
  return
end

-- check memcached (if enabled)
if memcached then
  local json = query_memcached()
  if json then
    ngx.say(json)
    return
  end
end

-- comment out networks which should not be queried
local networks = {  ["facebook"]  = ngx.thread.spawn(query_facebook),
                    ["pinterest"] = ngx.thread.spawn(query_pinterest),
                    ["twitter"]   = ngx.thread.spawn(query_twitter),
                 }

-- wait for each data fetch threads to return (or timeout)
local results = {}
for network,thread in pairs(networks) do
  local thread_ok, count = ngx.thread.wait(thread)
  if not thread_ok then
    fetching_error = true
  end
  results[network] = count
end

-- encode results into json and send to client
local json = cjson.encode(results)
ngx.say(json)
ngx.eof()

-- store in memcached if enabled
if memcached and not fetching_error then
  persist_memcached(json)
end

