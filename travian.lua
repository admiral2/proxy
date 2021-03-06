module(..., package.seeall)

local http = require('socket.http')
local mime = require('mime')
local ltn12 = require('ltn12')
require 'async'

require 'credentials'

local function yield_for(seconds)
    local expected = os.time() + seconds
    async.add_regular()
    while os.time() < expected do
      coroutine.yield()
    end
    async.remove_regular()
end

function filter(request, response)
  -- searching captcha on the page
  local captcha, captcha_key = string.match(response.body(), '<iframe src="(http://api.recaptcha.net/noscript??(k=[%a%d_]+&amp;lang=en))')
  
  if not captcha then
    -- print('not matched')
    -- yahoo, no captcha! proceeding
    return nil
  end
  
  -- print('got captcha: '..captcha)
  
  -- downloading google's nojavascript recaptcha page
  local captcha_page = http.request(captcha)
  -- print('got page: '..captcha_page)
  
  -- find image link
  -- src="image?c=03AHJ_VuvCYZT-aZL96WJa7bTVx6rlUcqAWPtNkM-zQ5NHKQYinkjcV5DT-u-qm5mfTgnqlqrKTwAzZWcMwo5cumK7bbSRddzQtevH1NuYwkfpj33cALtgJ3rygojWGaTJ_xhbGrOqly7G9fDZlEqb0qNVseZ517ui0w"
  local image_link = 'http://api.recaptcha.net/'..string.match(captcha_page, 'src="(image??c=[%d%a%-_]+)"')
  -- print('image link:'..image_link)
  
  -- <form action="" method="POST"><input type="hidden" name="recaptcha_challenge_field" id="recaptcha_challenge_field" value="03AHJ_Vus1DNaUUxmLppQiGmbYTEN4Yl1orZhsDZQhjeCedmTNUmjmBM4GiXagAfY8CDH7ibRywvz2HubPsnAJksY_LK5wp6o-Pi7wugdC81nOAC-1WQ-3EIqJ1VsIq9yFK0bCmDWJxark_OX_CXS7bXRQ6fP_qEH76A">
  local challenge = string.match(captcha_page, 'id="recaptcha_challenge_field" value="([%d%a%-_=]+)">')
  -- print('challenge:'..challenge)

  -- post image link to rosa server
  local captcha_id

  local status = 0
  repeat
    captcha_id = {}
    -- print('sending AG request, yield 1 sec')
    _, status = http.request {
      url = rosa_server..'/captcha/upload/'..mime.b64(image_link)..'/'..rosa_agent_version,
      headers = {['Authorization'] = 'Basic '..mime.b64(rosa_user..':'..rosa_password_sha1) },
      sink = ltn12.sink.table(captcha_id)
    }
    -- print('resp:', table.concat(captcha_id))
    yield_for(1)
  until status == 200

  captcha_id = table.concat(captcha_id)
  -- print('waiting id, yield 4 sec:'..captcha_id)
  
  -- yield in loop for 4 sec
  yield_for(4)

  -- print('waiting id2:'..captcha_id)
  
  -- yield in loop asking server for resolved, wait 1 sec
  local resolved
  local status = 0
  repeat
    resolved = {}
    -- print('waiting id, yield 1 sec:'..captcha_id)
    yield_for(1)
    _, status = http.request {
      url = rosa_server..'/captcha/'..captcha_id..'/'..rosa_agent_version,
      headers = {['Authorization'] = 'Basic '..mime.b64(rosa_user..':'..rosa_password) },
      sink = ltn12.sink.table(resolved)
    }
  until status == 200
  
  resolved = table.concat(resolved)
  -- print('resolved:'..resolved)

  -- recaptcha_challenge_field  02JU_v-DFLIW47OAVaPx6-S87AAUZnbWyPvKzSFx3tM_EY_GKOZbCCOlQ_KEI7ohYapxkgTeG7YQbPzWqTfkyslA-qU52MwvHC7t3MoEk3xCwMq7jvdeHZq34hqraoKuSq2NrddkeTecKvBlV0L2sA8oUcj2Pv3jhxe-sHyWkNon4Qgbh_1CApy7hQyeZ1Tf1-lu_9fxH08s1d15Kz373h0ZgoAubu2GXPmB631cDNykMTcEJ-ipJUVsKLepes7qvzjxqeZ_FJeBjDtk1nfnmHWq16KusB
  -- recaptcha_response_field may ullman
  local post_data = 
    'recaptcha_challenge_field='..url_encode(challenge)..
    '&recaptcha_response_field='..url_encode(resolved)..
    '&submit='..url_encode("I'm a human")
  -- print('post_data:'..post_data)

  -- print('original headers:'..table.concat(request.headers, '\r\n'))

  local google_request_headers = {
    ['Host'] = 'www.google.com',
    ['User-Agent'] = 'Mozilla/5.0 (Macintosh; U; PPC Mac OS X 10.4; en-US; rv:1.9.1.2) Gecko/20090729 Firefox/3.5.2', --request.headers['User-Agent'],
    ['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8', --request.headers['Accept'],
    ['Accept-Language'] = 'en-us,en;q=0.5', --request.headers['Accept-Language'],
    ['Referer'] = captcha,
    ['Content-Type'] = 'application/x-www-form-urlencoded',
    ['Content-Length'] = #post_data
  }

  -- post to google
  -- print('headers:'..table.concat(google_request_headers, '\r\n'))
  -- print('url', 'http://www.google.com/recaptcha/api/noscript?'..captcha_key)

  local recaptcha_key = {}
  _, status = http.request {
    method = 'POST',
    url = 'http://www.google.com/recaptcha/api/noscript?'..captcha_key,
    headers = google_request_headers,
    source = ltn12.source.string(post_data),
    sink = ltn12.sink.table(recaptcha_key)
  }
  
  recaptcha_key = table.concat(recaptcha_key)
  recaptcha_key = string.match(recaptcha_key, '<textarea[^>]+>([%a%d_\-]+)</textarea>')
  
  -- post to travian
  -- local host = string.match(url, '%a+ (http://[%a%d\./:-]+)')
  post_data = 
    'recaptcha_challenge_field='..url_encode(recaptcha_key)..
    '&recaptcha_response_field=manual_challenge'

  request.headers['Content-Type'] = 'application/x-www-form-urlencoded'
  request.headers['Content-Length'] = #post_data

  -- print('posting to travian')
  local result = {}
  _, status = http.request {
    method = 'POST',
    url = request.uri,
    headers = request_headers,
    source = ltn12.source.string(post_data),
    sink = ltn12.sink.table(result)
  }
  
  print('resolved captcha at', request.uri, '"'..resolved..'"')
  -- print('response:', status, '\r\n', table.concat(result))
  
  -- get result, pass back
  response.set_body(table.concat(result))
end

function pre(request, response)
  -- print('pre-filtering')
  local mimetype = response.headers('Content-Type')
  return string.find(request.uri(), 'travian') and mimetype and string.find(mimetype, 'text/html')
end
