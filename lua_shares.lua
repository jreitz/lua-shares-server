-- lua-shares server
-- by Jay Reitz <jreitz@gmail.com>
-- (inspired by tfrce/social-buttons-server)
--

local shares = {}

local config = {

  -- url_whitelist_regex:
  --   if set, respond only for urls meeting this PCRE pattern
  --   e.g. [[^http://([a-z0-9])?\.hubpages\.com/]]
  --   for general regex help, see http://perldoc.perl.org/perlretut.html
  --   NOTE: [[ and ]] string literal to prevent collisions with lua \ escapes
  url_whitelist_regex = nil,

  -- supported networks: "facebook", "pinterest", "twitter", "linkedin"
  http_fetch_default_networks = { "facebook", "pinterest", "twitter" },
  http_fetch_timeout = 3000, -- msecs

  -- memcached cache configuration:
  memcached = require "resty.memcached", -- set to false to disable caching
  memcached_ttl = 300, -- secs (0 is never expire)
  memcached_key_prefix = "luashares:", -- url is appended
  memcached_host = "127.0.0.1", -- only a single host is currently supported
  memcached_pool_size = 40,
}
shares.config = config


local function error_say(...)
  ngx.log(ngx.WARN, ...)
  -- return -- uncomment to disable showing errors in the response
  ngx.print("/* ", ...); ngx.say(" */")
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

local function validate_url_arg(url)
  if not url then
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    error_say("Missing required \"url\" parameter and no referer header provided")
    return ngx.exit(0)
  end
  if config.url_whitelist_regex and not ngx.re.match(url, config.url_whitelist_regex) then
    ngx.status = ngx.HTTP_FORBIDDEN
    error_say("Provided URL not allowed by this server")
    return ngx.exit(0)
  end
end

local function validate_networks_arg(fetch_networks)
  -- TODO: implement
end

local function parse_uri_args()
  -- parse url= param (or use Referer header if present)
  local url = ngx.req.get_uri_args()["url"]
  if not url then
    url = ngx.req.get_headers()["Referer"]
  end
  validate_url_arg(url)

  -- parse optional networks= param, expects comma seperated
  local fetch_networks = config.http_fetch_default_networks
  local networks_arg = ngx.req.get_uri_args()["networks"]
  if networks_arg then
    fetch_networks = csplit(networks_arg, ",")
  end
  validate_networks_arg(fetch_networks)

  return url, fetch_networks
end

local function get_req(host, options)
  local http = require "resty.http.simple"
  options.timeout = config.http_fetch_timeout
  return http.request(host, 80, options)
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
  local ok, err = memc:set_keepalive(0, config.memcached_pool_size) -- 0: no timeout of connections in pool
  if not ok then
    ngx.log(ngx.ERR, "Cannot set memcached keepalive: ", err)
  end
end

local function query_memcached(memc, url)
  -- memc is global because it is re-used to persist data
  memc:connect(config.memcached_host, 11211)
  local res, err = memc:get(config.memcached_key_prefix .. url)
  if res then
    -- if the get succeeded, we're done with this memcached connection
    set_memcached_pool(memc)
  end
  return res
end

local function persist_memcached(memc, url, json)
  local ok, err = memc:set(config.memcached_key_prefix .. url, json, config.memcached_ttl)
  if not ok then
    ngx.log(ngx.ERR, "Cannot persist lua-shares to memcached: ", err)
    return
  end
  set_memcached_pool(memc)
end

local function spawn_fetch_threads(fetch_networks, url)
  local networks = {}
  for i,name in ipairs(fetch_networks) do
    networks[name] = ngx.thread.spawn(shares["http_query_".. name], url)
  end
  return networks
end

-- wait for each data fetch threads to return (or timeout)
local function wait_for_fetch_threads(networks)
  local results, fetching_error = {}, nil
  for network,thread in pairs(networks) do
    local thread_ok, count = ngx.thread.wait(thread)
    if not thread_ok then
      fetching_error = true
    end
    results[network] = count
  end
  return results, fetching_error
end

function shares.http_query_twitter(url)
  local res, err = get_req("urls.api.twitter.com", {
    path    = "/1/urls/count.json",
    query   = { ["url"] = url },
  })

  if is_good_http_response("twitter", res, err) then
    res.data = cjson.decode(res.body)
    if res.data and res.data.count then
      return res.data.count
    end
  end
  return -1
end

function shares.http_query_facebook(url)
  local res, err = get_req("graph.facebook.com", {
    path    = "/",
    query   = { ["id"] = url },
    headers = { ["Accept"] = "application/json" },
  })

  if is_good_http_response("facebook", res, err) then
    res.data = cjson.decode(res.body)
    if res.data and res.data.shares then
      return res.data.shares
    else
      return 0 -- fb does not include "shares" key for un-shared url
    end
  end
  return -1
end

function shares.http_query_pinterest(url)
  local res, err = get_req("api.pinterest.com", {
    path    = "/v1/urls/count.json",
    query   = { ["url"] = url, ["callback"] = "" },
    headers = { ["Accept"] = "application/json" },
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

function shares.http_query_linkedin(url)
  local res, err = get_req("www.linkedin.com", {
    path    = "/countserv/count/share",
    query   = { ["url"] = url, ["format"] = "json" },
  })

  if is_good_http_response("linkedin", res, err) then
    res.data = cjson.decode(res.body)
    if res.data and res.data.count then
      return res.data.count
    end
  end
  return -1
end

function shares.get_counts()
  local url, fetch_networks = parse_uri_args()

  -- check memcached (if enabled)
  local memc
  if config.memcached then
    memc = config.memcached:new()
    local json = query_memcached(memc, url)
    if json then
      ngx.say(json); return
    end
  end

  -- dispatch and wait for light-threads to get counts via HTTP apis
  local networks = spawn_fetch_threads(fetch_networks, url)
  local results, fetching_error = wait_for_fetch_threads(networks)

  -- encode results into json and send to client
  local json = cjson.encode(results)
  ngx.say(json)
  ngx.eof()

  -- store in memcached if enabled
  if memc and not fetching_error then
    persist_memcached(memc, url, json)
  end
end

return shares
