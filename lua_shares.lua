-- lua-shares server
-- by Jay Reitz <jreitz@gmail.com>
-- (inspired by tfrce/social-buttons-server)
--

-- http fetch configuration
http_fetch_default_networks = { "facebook", "pinterest", "twitter" }
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

local function csplit(str, sep)
  local ret={}
  local n=1
  for w in str:gmatch("([^"..sep.."]*)") do
    ret[n]=ret[n] or w -- only set once (so the blank after a string is ignored)
    if w=="" then n=n+1 end -- step forwards on a blank but not a string
  end
  return ret
end

local function parse_uri_args()
  -- parse url= param
  local url = ngx.req.get_uri_args()["url"]
  if not url then
    error_say("Missing required \"url\" parameter")
    ngx.exit(ngx.ERROR)
  end

  -- parse optional networks= param, expects comma seperated
  local fetch_networks = http_fetch_default_networks
  local networks_arg = ngx.req.get_uri_args()["networks"]
  if networks_arg then
    fetch_networks = csplit(networks_arg, ",")
    -- TODO: validate network list
  end

  return url, fetch_networks
end

local function is_good_http_response(name, res, err)
  if res then
    if res.status == ngx.HTTP_OK then
      return true
    end
    error_say("http bad response (", res.status, ") from ", name, ", response: ", res.body)
  else
    error_say("http ", name, " error: ", err)
  end
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

function http_query_twitter()
  local http = require "resty.http.simple"
  local res, err = http.request("urls.api.twitter.com", 80, {
    path    = "/1/urls/count.json",
    query   = { ["url"] = url },
    timeout = http_fetch_timeout,
  })

  if is_good_http_response("twitter", res, err) then
    res.data = cjson.decode(res.body)
    if res.data and res.data.count then
      return res.data.count
    end
  end
  return -1
end

function http_query_facebook()
  local http = require "resty.http.simple"
  local res, err = http.request("graph.facebook.com", 80, {
    path    = "/",
    query   = { ["id"] = url },
    headers = { ["Accept"] = "application/json" },
    timeout = http_fetch_timeout,
  })

  if is_good_http_response("facebook", res, err) then
    res.data = cjson.decode(res.body)
    if res.data and res.data.shares then
      return res.data.shares
    else
      -- facebook does not include "shares" key for un-shared url
      return 0
    end
  end
  return -1
end

function http_query_pinterest()
  local http = require "resty.http.simple"
  local res, err = http.request("api.pinterest.com", 80, {
    path    = "/v1/urls/count.json",
    query   = { ["url"] = url, ["callback"] = "" },
    headers = { ["Accept"] = "application/json" },
    timeout = http_fetch_timeout,
  })

  if is_good_http_response("pinterest", res, err) then
    -- first, remove surrounding ( and )
    local scrubbed_body = string.match(res.body, "^%(([^)]+)")
    res.data = cjson.decode(scrubbed_body)
    if res.data and res.data.count then
      return res.data.count
    end
  end
  return -1
end

function http_query_linkedin()
  local http = require "resty.http.simple"
  local res, err = http.request("www.linkedin.com", 80, {
    path    = "/countserv/count/share",
    query   = { ["url"] = url, ["format"] = "json" },
    timeout = http_fetch_timeout,
  })

  if is_good_http_response("linkedin", res, err) then
    res.data = cjson.decode(res.body)
    if res.data and res.data.count then
      return res.data.count
    end
  end
  return -1
end


--
-- main

url, fetch_networks = parse_uri_args()

-- check memcached (if enabled)
if memcached then
  local json = query_memcached()
  if json then
    ngx.say(json)
    return
  end
end

-- dispatch light-threads to via counts via HTTP apis
local networks = {}
for i,name in ipairs(fetch_networks) do
  networks[name] = ngx.thread.spawn(_G["http_query_".. name])
end

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

