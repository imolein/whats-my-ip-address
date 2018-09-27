#!/usr/bin/env lua5.3
--- Whats my IP address
-- Yet another Whats my IP address - Service

local http_server = require('http.server')
local http_headers = require('http.headers')
local cerrno = require('cqueues.errno')
local lfs = require('lfs')
local mimetypes = require('mimetypes')


----------------------------------------------
---   Load configuration or use defaults   ---
----------------------------------------------
local function loadconfig(cfg)
  local conf, err = loadfile(cfg)
  
  if not conf and err then
    io.stdout:write(string.format('ERROR: Can\'t load config %s. Use defaults!\n', cfg))

    return { 
      host = 'localhost',
      port = 9090,
      html_root = './html/',
      domain = 'localhost'
    }
  end
  
  return conf()
end

local CONFIG
if arg[1] and arg[1] == '-c' and arg[2] then
  CONFIG = loadconfig(arg[2])
else
  CONFIG = loadconfig('config.cfg.lua')
end
----------------------------------------------

----------------------------------------------
---            Helper functions            ---
----------------------------------------------
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
  if con_ip == '127.0.0.1' and ( req_headers:has('x-real-ip') or req_headers:has('x-forwarded-for') ) then
      -- preffer x-real-ip over x-forwarded-for
      return req_headers:get('x-real-ip') or req_headers:get('x-forwarded-for')
  end

  return con_ip
end

-- opens and read the index.html, replaces the
-- placeholders and returns it
local function gen_index_site(ip)
  local file, err, errnr = io.open(CONFIG.html_root .. 'index.html', 'r')
  
  if not file and err then return nil, errnr end
    
  local index = file:read('*a')
  file:close()
  
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
  local resp_content, errnr = gen_index_site(ip)
  
  if resp_content then
    res_headers:append(':status', '200')
    res_headers:append('content-type', 'text/html')
    stream:write_headers(res_headers, method == 'HEAD')
    if method ~= 'HEAD' then
      stream:write_body_from_string(resp_content)
    end
  else
    err_responder(stream, method, get_err_status_code(errnr))
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
    local fd, err, errnr = io.open(path, 'rb')

    if fd then
      res_headers:append(':status', '200')
      res_headers:append('content-type', mimetypes.guess(path))
      assert(stream:write_headers(res_headers, method == 'HEAD'))

      if method ~= 'HEAD' then
        assert(stream:write_body_from_file(fd))
      end
    else
      err_responder(stream, method, get_err_status_code(errnr), err)
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
  local msg = op .. " on " .. tostring(context) .. " failed"
		if err then
			msg = msg .. ": " .. tostring(err)
		end
  assert(io.stderr:write(msg, "\n"))
end
----------------------------------------------


----------------------------------------------
---              Start server              ---
----------------------------------------------
local server = assert(http_server.listen({
        host = CONFIG.host,
        port = CONFIG.port,
        onstream = wmia_handler,
        onerror = error_handler
      }))

assert(server:listen())

do
  local _, host, port = server:localname()
  io.stderr:write(string.format('Server is running on %s:%d\n', host, port))
end

assert(server:loop())
----------------------------------------------