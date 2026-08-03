-- example HTTP POST script sending a JSON payload
-- run: ./wrq -s scripts/post-json.lua http://127.0.0.1:8080/api

local json = require("json")

local payload = {
  user    = "alice",
  active  = true,
  roles   = { "admin", "editor" },
  limits  = { requests = 100, window = 60 },
}

wrk.method = "POST"
wrk.body   = json.encode(payload)
wrk.headers["Content-Type"] = "application/json"

-- example: decode a JSON response in the per-response callback
-- response = function(status, headers, body)
--   local data = json.decode(body)
--   -- inspect data.some_field here
-- end
