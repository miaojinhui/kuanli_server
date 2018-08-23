-------------------------------------------------------------
---! @file
---! @brief web socket的客户连接
--------------------------------------------------------------

---!
local skynet = require "skynet"

---!
local clsHelper = require "ClusterHelper"
local taskHelper = require "TaskHelper"

local AgentUtils = require "AgentUtils"

---!
local userInfo  = {}
local agentInfo = {}
local agentUtil = nil

local handler = {}
function handler.on_open(ws)
    agentInfo.last_update = os.time()
end

function handler.on_message(ws, msg)
    agentInfo.last_update = os.time()

    local worker = function ()
        agentUtil:command_handler(msg)
    end

    xpcall( function()
        taskHelper.queue_task(worker)
    end,
    function(err)
        skynet.error(err)
        skynet.error(debug.traceback())
    end)
end

function handler.on_error(ws, msg)
    agentUtil:kickMe()
end

function handler.on_close(ws, code, reason)
    agentUtil:kickMe()
end

---!
local utilCallBack = {}

---!
local CMD = {}

---! @brief start service
function CMD.start (info, header)
    if userInfo.client_sock then
        return
    end

    local id = info.client_fd
    socket.start(id)
    pcall(function ()
        userInfo.client_sock = websocket.new(id, header, handler)
    end)
    if userInfo.client_sock then
        skynet.fork(function ()
            userInfo.client_sock:start()
        end)
    end

    agentInfo = info
    agentInfo.last_update = skynet.time()

    skynet.fork(function()
        local heartbeat = 7   -- 7 seconds to send heart beat
        local timeout   = 60  -- 60 seconds, 1 minutes
        while true do
            local now = skynet.time()
            if now - agentInfo.last_update >= timeout then
                agentUtil:kickMe()
                return
            end

            agentUtil:sendHeartBeat()
            skynet.sleep(heartbeat * 100)
        end
    end)

    return 0
end

function CMD.sendProtocolPacket (packet)
    if userInfo.client_sock then
        userInfo.client_sock:send_binary(packet)
    end
end


---! @brief 通知agent主动结束
function CMD.disconnect ()
    agentUtil:reqQuit(agentInfo.client_fd)

    if userInfo.client_sock then
        userInfo.client_sock:close()
        userInfo.client_sock = nil
    end

    skynet.exit()
end


skynet.start(function()
    ---! 注册skynet消息服务
    skynet.dispatch("lua", function(_,_, cmd, ...)
        local f = CMD[cmd]
        if f then
            local ret = f(...)
            if ret then
                skynet.ret(skynet.pack(ret))
            end
        else
            skynet.error("unknown command ", cmd)
        end
    end)

    userInfo.sign = os.time()
    agentUtil = AgentUtils.create(agentInfo, userInfo, CMD, utilCallBack)
end)

