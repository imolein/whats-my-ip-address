#!/usr/bin/env lua5.4
--- Whats my IP address
-- Yet another Whats my IP address - Service

local http_server = require('http.server')
local http_headers = require('http.headers')
local cerrno = require('cqueues.errno')
local lfs = require('lfs')
local mimetypes = require('mimetypes')

local logger

----------------------------------------------
---   Load configuration or use defaults   ---
----------------------------------------------
local ENV_VARS = { 'WMIA_HOST', 'WMIA_PORT', 'WMIA_HTML_ROOT', 'WMIA_DOMAIN' }
local DEFAULTS = {
  host = '0.0.0.0',
  port = 9090,
  html_root = './html/',
  domain = 'localhost'
}
local CONFIG

-- check if path exists
local function exists(path)
  local ok, _, errno = lfs.attributes(path, 'ino')

  return (ok or errno == 13) and true or false
end

-- getting config values from environment variables
-- for example when running in docker
local function apply_env_config(conf)
  for _, var in ipairs(ENV_VARS) do
    local val = os.getenv(var)

    if val then
      local opt = var:sub(6):lower()
      logger('INFO', 'Setting value of option %q to %q given by %s', opt, val, var)
      conf[opt] = val
    end
  end
end

-- apply default settings which are not set
local function apply_defaults(conf)
  for k, v in pairs(DEFAULTS) do
    if conf[k] == nil then
      logger('INFO', 'Settings %q for option %q, because it was nil', v, k)
      conf[k] = v
    end
  end
end

-- loading the configuration, from file, environment and/or default values
local function load_config(cfg)
  local conf = {}

  if exists(cfg) then
    logger('INFO', 'Loading config from file %s', cfg)
    local fh = assert(io.open(cfg))
    local content = fh:read('*a')
    fh:close()

    local fn = assert(load(content, cfg))
    conf = fn()
  end

  apply_env_config(conf)
  apply_defaults(conf)

  return conf
end

----------------------------------------------

----------------------------------------------
---            Helper functions            ---
----------------------------------------------

-- simple logger
function logger(level, msg, ...)
  level = level:upper()

  io.write(('[%s] %s\n'):format(level, msg:format(...)))
  io.flush()
end

-- takes linux system errors and return fitting
-- http status code
local function get_err_status_code(errnr)
  if errnr == cerrno.ENOENT then
    return '404'
  elseif errnr == cerrno.EACCES then
    return '403'
  else
    return '500'
  end
end

-- return the ip address of the requester and
-- preffer the X-Real-IP over X-Forwared-For if
-- proxied
local function get_req_ip(con_ip, req_headers)
  local ip = con_ip == '127.0.0.1'
    and (req_headers:has('x-real-ip') or req_headers:has('x-forwarded-for'))
    or con_ip

  return ip
end

-- opens and read the index.html, replaces the
-- placeholders and returns it
local function gen_index_site(ip)
  local fh, _, errno = io.open(CONFIG.html_root .. 'index.html', 'r')

  if not fh then return nil, errno end

  local index = fh:read('*a')
  fh:close()

  return index:gsub('{{ IP }}', ip):gsub('{{ DOMAIN }}', CONFIG.domain)
end
----------------------------------------------

----------------------------------------------
---          Responder functions           ---
----------------------------------------------
-- returns error pages
local function err_responder(stream, method, status, msg)
  local res_headers = http_headers.new()
  local http_state = {
    ['403'] = 'Forbidden',
    ['404'] = 'Not Found',
    ['500'] = 'Internatl Server Error'
  }
  msg = msg or http_state[status]

  res_headers:append(':status', status)
  res_headers:append('content_type', 'text/plain')
  stream:write_headers(res_headers, method == 'HEAD')

  if method ~= 'HEAD' then
    assert(stream:write_body_from_string('Failed with: ' .. msg .. '\n'))
  end
end

-- returns IP address in plain text
local function plaintxt_responder(stream, method, ip)
  local res_headers = http_headers.new()

  res_headers:append(':status', '200')
  res_headers:append('content-type', 'text/plain')
  stream:write_headers(res_headers, method == 'HEAD')

  if method ~= 'HEAD' then
    stream:write_body_from_string(ip)
  end
end

-- returns fancy html page with IP address
local function html_responder(stream, method, ip)
  local res_headers = http_headers.new()
  local resp_content, errno = gen_index_site(ip)

  if resp_content then
    res_headers:append(':status', '200')
    res_headers:append('content-type', 'text/html')
    stream:write_headers(res_headers, method == 'HEAD')
    if method ~= 'HEAD' then
      stream:write_body_from_string(resp_content)
    end
  else
    err_responder(stream, method, get_err_status_code(errno))
  end
end

-- returns IP address in JSON
local function json_responder(stream, method, ip)
  local res_headers = http_headers.new()

  res_headers:append(':status', '200')
  res_headers:append('content-type', 'application/json')
  stream:write_headers(res_headers, method == 'HEAD')

  if method ~= 'HEAD' then
    stream:write_body_from_string(('{ "ip": %q }'):format(ip))
  end
end
----------------------------------------------

----------------------------------------------
---           Serve static files           ---
----------------------------------------------
-- serves static files, which are located under
-- $html_root/static
local function serve_static(stream, req_path, method)
  local res_headers = http_headers.new()
  local path = CONFIG.html_root .. req_path
  local f_type = lfs.attributes(path, 'mode')

  if f_type == 'file' then
    local fh, err, errno = io.open(path, 'rb')

    if fh then
      res_headers:append(':status', '200')
      res_headers:append('content-type', mimetypes.guess(path))
      assert(stream:write_headers(res_headers, method == 'HEAD'))

      if method ~= 'HEAD' then
        assert(stream:write_body_from_file(fh))
      end

      fh:close()
    else
      err_responder(stream, method, get_err_status_code(errno), err)
    end
  else
    err_responder(stream, method, '500')
  end
end
----------------------------------------------

----------------------------------------------
---    Whats my IP address main handler    ---
----------------------------------------------

local function wmia_handler(_, stream)
  local cli_agents = { curl = true, wget = true, httpie = true }
  local req_headers = assert(stream:get_headers())  -- get header object from stream
  local req_method = req_headers:get(':method')     -- get method from header object
  local req_agent = req_headers:get('user-agent'):lower():match('^(%w+)/.*$')
  local req_path = req_headers:get(':path'):lower() -- get path from, beginning from the last /
  local ip

  logger('INFO', '[%s] "%s %s HTTP/%g" "%s"',
      os.date("%d/%b/%Y:%H:%M:%S %z"),
      req_method or '-',
      req_path or '-',
      stream.connection.version,
      req_headers:get('user-agent') or '-'
    )

  -- only GET and HEAD is allowed, response to others with status 403
  if req_method == 'GET' or req_method == 'HEAD' then
    ip = get_req_ip(select(2, stream:peername()), req_headers)

    if req_path:match('^/$') then
      if cli_agents[req_agent] then
        plaintxt_responder(stream, req_method, ip)
      else
        html_responder(stream, req_method, ip)
      end
    elseif req_path:match('^/json$') then
      json_responder(stream, req_method, ip)
    elseif req_path:match('^/html$') then
      html_responder(stream, req_method, ip)
    elseif req_path:match('^/plain$') then
      plaintxt_responder(stream, req_method, ip)
    elseif req_path:match('^/static.*$') then
      serve_static(stream, req_path:sub(2), req_method)
    else
      html_responder(stream, req_method, ip)
    end
  end
end

-- error handler, which writes error details to console
local function error_handler(_, context, op, err)
  local msg = ('%s on %s failed'):format(op, tostring(context))

  if err then
    msg = msg .. ": " .. tostring(err)
  end

  logger('ERROR', msg)
end
----------------------------------------------


----------------------------------------------
---              Start server              ---
----------------------------------------------
if arg[1] and arg[1] == '-c' and arg[2] then
  CONFIG = load_config(arg[2])
else
  CONFIG = load_config('config.cfg')
end

local server = assert(http_server.listen({
  host = CONFIG.host,
  port = CONFIG.port,
  onstream = wmia_handler,
  onerror = error_handler
}))

assert(server:listen())

do
  local _, host, port = server:localname()
  logger('INFO', 'Server is running on %s:%d', host, port)
end

assert(server:loop())
----------------------------------------------
